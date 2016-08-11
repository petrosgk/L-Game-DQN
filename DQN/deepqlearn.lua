require 'nn'
require 'optim'
require 'utils'

torch.setdefaulttensortype('torch.FloatTensor')

local DQN = {}

function DQN.init(state_size, actions)
  -- Maximum number of memories (= games) that we will save for training
  DQN.experience_size = 10000
  -- number of games to sample from replay memory on each recall
  DQN.sampleN = 10
  -- gamma is a crucial parameter that controls how much plan-ahead the agent does. In [0,1]
  -- Determines the amount of weight placed on the utility of the state resulting from an action.
  DQN.gamma = 0.9
  -- controls exploration exploitation tradeoff
  -- a higher epsilon means we are more likely to choose random actions
  DQN.epsilon = 0.05
  -- input that goes into neural net
  DQN.net_inputs = state_size
  -- size of each hidden layer of the neural net
  DQN.hidden_nodes_L1 = 512
  DQN.hidden_nodes_L2 = 512
  -- output of the neural net
  DQN.net_outputs = actions;
  -- define neural net architecture
  DQN.net = nn.Sequential()
  DQN.net:add(nn.Linear(DQN.net_inputs, DQN.hidden_nodes_L1))
  DQN.net:add(nn.ReLU())
  DQN.net:add(nn.Linear(DQN.hidden_nodes_L1, DQN.hidden_nodes_L2))
  DQN.net:add(nn.ReLU())
  DQN.net:add(nn.Linear(DQN.hidden_nodes_L2, DQN.net_outputs))
  DQN.criterion = nn.MSECriterion()
  -- is learning enabled (true by default)
  DQN.learning = true;
  -- coefficients for regression
  DQN.coefL1 = 0
  DQN.coefL2 = 0
  -- parameters for optim.adadelta
  DQN.parameters, DQN.gradParameters = DQN.net:getParameters()
  -- replay memory table
  DQN.experience = {}
  -- These windows track old states, actions and rewards over time.
  DQN.state_window = {}
  DQN.action_window = {}
  DQN.reward_window = {}
  -- random gen
  DQN.gen = torch.Generator()
  torch.seed(DQN.gen)
  -- various housekeeping variables
  DQN.age = 0; -- incremented every backward()
  DQN.forward_passes = 0  -- number of times we've called forward
  DQN.experience_count = 0  -- Count of games in the replay memory
end

-- loads an already trained net
function DQN.loadModel(t_net)
  DQN.net = t_net
end

-- returns a random action
function DQN.random_action()
  return torch.random(DQN.gen, DQN.net_outputs)
end

-- compute the value of doing any action in the given state
-- and return the argmax action and its value
function DQN.policy(state)
  local action_values = DQN.net:forward(state);

  local max_val = action_values[1]
  local max_index = 1

  -- find maximum output and note its index and value
  for i = 2, DQN.net_outputs do
    if action_values[i] > max_val then
      max_val = action_values[i]
      max_index = i
    end
  end

  return {action = max_index, value = max_val};
end

--[[ This function computes an action by either:
1. Giving the current state to the network and letting it choose the best action
2. Choosing a random action
--]]
function DQN.forward(state)
  local action
  -- if we have enough (state, action) pairs in our memory to fill up
  -- our network input then we'll proceed to let our network choose the action
  if DQN.forward_passes > 0 then
    local net_input = torch.Tensor(state)
    -- use epsilon probability to choose whether we use network action or random action
    if randf(DQN.gen, 0, 1) < DQN.epsilon then
      action = DQN.random_action();
    else
      -- otherwise use our policy to make decision
      local best_action = DQN.policy(net_input);
      action = best_action.action; -- this is the action number
    end
  else
    -- pathological case that happens first few iterations when we can't
    -- fill up our network inputs. Just default to random action in this case
    action = DQN.random_action();
  end
  DQN.forward_passes = DQN.forward_passes + 1
  return action;
end

-- adds the state into the time window
function DQN.addState(state)
  if not DQN.learning then
    return
  end
  -- add the state
  table.insert(DQN.state_window, state)
end

-- adds the chosen action into the time window
function DQN.addAction(action)
  if not DQN.learning then
    return
  end
  -- add the action chosen
  table.insert(DQN.action_window, action)
end

-- adds the reward for the previous state-action pair
function DQN.addReward(reward)
  if not DQN.learning then
    return
  end
  -- add reward
  table.insert(DQN.reward_window, reward)
end

function DQN.computeGradient(inputs, targets)
  -- create training function to give to optim.adadelta
  local feval = function(x)
    -- get new network parameters
    if x ~= DQN.parameters then
      DQN.parameters:copy(x)
    end
    -- reset gradients
    DQN.gradParameters:zero()
    -- evaluate function for complete mini batch
    local outputs = DQN.net:forward(inputs)
    local f = DQN.criterion:forward(outputs, targets)
    -- estimate df/dW
    local df_do = DQN.criterion:backward(outputs, targets)
    DQN.net:backward(inputs, df_do)
    -- penalties (L1 and L2):
    if DQN.coefL1 ~= 0 or DQN.coefL2 ~= 0 then
      -- locals:
      local norm,sign = torch.norm,torch.sign
      -- Loss:
      f = f + DQN.coefL1 * norm(DQN.parameters,1)
      f = f + DQN.coefL2 * norm(DQN.parameters,2)^2/2
      -- Gradients:
      DQN.gradParameters:add( sign(DQN.parameters):mul(DQN.coefL1) + DQN.parameters:clone():mul(DQN.coefL2) )
    end
    -- return f and df/dX
    return f, DQN.gradParameters
  end
  -- fire up optim.adadelta
  local adadeltaConfig = {rho = 0.95, eps = 1e-6}
  local adadeltaState = {}
  optim.adadelta(feval, DQN.parameters, adadeltaConfig, adadeltaState)
end

--[[
This function trains the network using the rewards resulting from all the actions
chosen for all the previous states leading up to the terminal state.
It will save this past experience which consists of:
The terminal state and, for every previous state, the action chosen, whether a reward
was obtained, and the next state that resulted from the action.
After that, it will train the network this experience.
--]]
function DQN.backward()
  -- if learning is turned off then don't do anything
  if not DQN.learning then
    return
  end

  DQN.age = DQN.age + 1;

  local num_states = #DQN.state_window

  local inputs = torch.Tensor(num_states - 1, DQN.net_inputs)
  local targets = torch.Tensor(num_states - 1, DQN.net_outputs)

  --[[ a game experience consists of all the experience tuples [state0,action0,reward0,state1]
	acquired during a game -]]
  local game_e = {}

  -- start from the terminal state and go backwards until the initial state
  for n = num_states, 2, - 1 do
    local state0 = DQN.state_window[n-1]
    local action0 = DQN.action_window[n-1]
    local reward0 = DQN.reward_window[1]
    local state1 = DQN.state_window[n]

    -- create experience
    local e = {state0, action0, reward0, state1}
    -- add experience to the total experience acquired on this game
    table.insert(game_e, e)

    -- start training
    local all_outputs = DQN.net:forward(torch.Tensor(state0))
    inputs[n-1] = torch.Tensor(state0)
    targets[n-1] = all_outputs:clone()
    pred = targets[n-1][action0]
    if n == num_states then -- if terminal state
      targets[n-1][action0] = reward0
    else
      local best_action = DQN.policy(torch.Tensor(state1))
      targets[n-1][action0] = DQN.gamma * best_action.value
    end
  end

  DQN.computeGradient(inputs, targets)

  -- add this game and the experiences acquired with it to the replay memory table
  if DQN.experience_count < DQN.experience_size then
    table.insert(DQN.experience, game_e)
    DQN.experience_count = DQN.experience_count + 1
  else
    -- if max size for replay memory reached start replacing older experiences
    table.remove(DQN.experience, 1)
    table.insert(DQN.experience, game_e)
  end

  -- free memory
  DQN.state_window = {}
  DQN.action_window = {}
  DQN.reward_window = {}
  game_e = {}

  if DQN.experience_count >= DQN.sampleN then
    for N = 1, DQN.sampleN do
      -- sample a random game from replay memory
      local re = DQN.experience[torch.random(DQN.gen, DQN.experience_count)]
      -- each game consists of a number of experiences
      local numExp = #re
      inputs = torch.Tensor(numExp, DQN.net_inputs)
      targets = torch.Tensor(numExp, DQN.net_outputs)
      for n = 1, numExp do
        local e = re[n]
        local state0 = e[1]
        local action0 = e[2]
        local reward0 = e[3]
        local state1 = e[4]
        -- start training
        local all_outputs = DQN.net:forward(torch.Tensor(state0))
        inputs[n] = torch.Tensor(state0)
        targets[n] = all_outputs:clone()
        if n == 1 then -- if terminal state
          targets[n][action0] = reward0
        else
          local best_action = DQN.policy(torch.Tensor(state1))
          targets[n][action0] = DQN.gamma * best_action.value
        end
      end
      DQN.computeGradient(inputs, targets)
    end
  end

end

return DQN
