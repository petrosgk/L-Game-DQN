require 'nn'
require 'optim'
require 'utils'

local board = require 'board'

local AI_Player = {}

-- initialize player
function AI_Player:initPlayer(o, playerId, LPawn, NPawn1, NPawn2)
  o = o or {}
  setmetatable(o, self)
  self.__index = self
  o.playerId = playerId
  o.LPawn = LPawn
  o.NPawn1 = NPawn1
  o.NPawn2 = NPawn2
  -- legal moves for the current state
  o.legalActions = {}
  -- agent reward parameters
  o.REWARD_FOR_LOSS = -1
  o.REWARD_FOR_DRAW = 0
  o.REWARD_FOR_WIN = 1
  o.REWARD_FOR_MOVE = 0
  -- track cumulative reward of agent
  o.reward_tot = 0
  -- Maximum number of memories (= games) that we will save for training
  o.experience_size = 25000
  -- number of games to sample from replay memory on each recall
  o.sampleN = 10
  -- gamma is a crucial parameter that controls how much plan-ahead the agent does. In [0,1]
  -- Determines the amount of weight placed on the utility of the state resulting from an action.
  o.gamma = 0.9
  -- controls exploration exploitation tradeoff
  -- a higher epsilon means we are more likely to choose random actions
  o.epsilon = 0.05
  -- min value epsilon is allowed to reach
  o.epsilon_min = 0.01
  -- target network update frequency
  o.tau = 1
  -- epsilon annealing factor
  -- controls the annealing rate of epsilon
  o.annealing_factor = 100000
  -- input that goes into neural net
  o.net_inputs = 16
  -- size of hidden layer of the neural net
  o.hidden_nodes = 512
  -- output of the neural net
  o.net_outputs = 128
  -- define neural net architecture
  o.net = nn.Sequential()
  o.net:add(nn.Linear(o.net_inputs, o.hidden_nodes))
  o.net:add(nn.ReLU(true))
  o.net:add(nn.Linear(o.hidden_nodes, o.hidden_nodes))
  o.net:add(nn.ReLU(true))
  o.net:add(nn.Linear(o.hidden_nodes, o.net_outputs))
  o.criterion = nn.MSECriterion()
  -- target network
  o.target_net = o.net:clone()
  -- target network always in eval mode
  o.target_net:evaluate()
  -- is learning enabled (false by default)
  o.learning = false;
  -- parameters for optim.adadelta
  o.parameters, o.gradParameters = o.net:getParameters()
  -- replay memory table
  o.experience = {}
  -- These windows track old states, actions and rewards over time.
  o.state_window = {}
  o.action_window = {}
  o.reward_window = {}
  -- random gen
  o.gen = torch.Generator()
  torch.seed(o.gen)
  -- various housekeeping variables
  o.age = 0; -- incremented every backward()
  o.forward_passes = 0  -- number of times we've called forward
  o.experience_count = 0  -- Count of games in the replay memory
  return o
end

-- loads an already trained net
function AI_Player:loadModel(t_net)
  self.net = t_net
end

-- returns a random action
function AI_Player:random_action()
  return torch.random(self.gen, self.net_outputs)
end

-- compute the value of doing any action in the given state
-- and return the argmax action and its value
function AI_Player:policy(state)
  local action_values = self.net:forward(state);

  local max_val = action_values[1]
  local max_index = 1

  -- find maximum output and note its index and value
  for i = 2, self.net_outputs do
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
function AI_Player:forward(state)
  local action
  -- if we have enough (state, action) pairs in our memory to fill up
  -- our network input then we'll proceed to let our network choose the action
  if self.forward_passes > 0 then
    local net_input = torch.FloatTensor(state)
    -- use epsilon probability to choose whether we use network action or random action
    if randf(self.gen, 0, 1) < self.epsilon then
      action = self:random_action();
    else
      -- otherwise use our policy to make decision
      local best_action = self:policy(net_input);
      action = best_action.action; -- this is the action number
    end
  else
    -- pathological case that happens first few iterations when we can't
    -- fill up our network inputs. Just default to random action in this case
    action = self:random_action();
  end
  self.forward_passes = self.forward_passes + 1
  return action;
end

-- adds the state into the time window
function AI_Player:addState(state)
  if not self.learning then
    return
  end
  -- add the state
  table.insert(self.state_window, state)
end

-- adds the chosen action into the time window
function AI_Player:addAction(action)
  if not self.learning then
    return
  end
  -- add the action chosen
  table.insert(self.action_window, action)
end

-- adds the reward for the previous state-action pair
function AI_Player:addReward(reward, isLast)
  if not self.learning then
    return
  end
  -- add reward
  if isLast then
    self.reward_window[#self.reward_window] = reward
  else
    table.insert(self.reward_window, reward)
  end
end

function AI_Player:computeGradient(inputs, targets)
  -- create training function to give to optim.sgd
  local feval = function(x)
    -- get new network parameters
    if x ~= self.parameters then
      self.parameters:copy(x)
    end
    -- reset gradients
    self.gradParameters:zero()
    -- evaluate function for complete mini batch
    local outputs = self.net:forward(inputs)
    local f = self.criterion:forward(outputs, targets)
    -- estimate df/dW
    local df_do = self.criterion:backward(outputs, targets)
    self.net:backward(inputs, df_do)
    -- return f and df/dX
    return f, self.gradParameters
  end
  -- fire up optim.sgd
  local sgdConfig = {learningRate = 1, learningRateDecay = 1e-4,
    momentum = 0.9, dampening = 0, nesterov = true}
  local rmspropConfig = {learningRate = 0.001}
  optim.adadelta(feval, self.parameters, {})
end

--[[
This function trains the network using the rewards resulting from all the actions
chosen for all the previous states leading up to the terminal state.
It will save this past experience which consists of:
The terminal state and, for every previous state, the action chosen, whether a reward
was obtained, and the next state that resulted from the action.
After that, it will train the network this experience.
--]]
function AI_Player:backward()
  -- if learning is turned off then don't do anything
  if not self.learning then
    return
  end

  self.age = self.age + 1;

  local num_states = #self.state_window

  --[[ a game experience consists of all the experience tuples [state0,action0,reward0,state1]
  acquired during a game -]]
  local game_e = {}

  -- from the initial state until the terminal state
  for n = 2, num_states do
    local state0 = self.state_window[n-1]
    local action0 = self.action_window[n-1]
    local reward0 = self.reward_window[n-1]
    local state1 = self.state_window[n]

    -- convert to byte tensors to save memory
    state0 = torch.ByteTensor(state0)
    action0 = torch.ByteTensor({action0})
    state1 = torch.ByteTensor(state1)

    -- create experience
    local e = {state0, action0, reward0, state1}
    -- add experience to the total experience acquired on this game
    table.insert(game_e, e)
  end

  -- add this game and the experiences acquired with it to the replay memory table
  if self.experience_count < self.experience_size then
    table.insert(self.experience, game_e)
    self.experience_count = self.experience_count + 1
  else
    -- if max size for replay memory reached start replacing older experiences
    table.remove(self.experience, 1)
    table.insert(self.experience, game_e)
  end

  -- free memory
  self.state_window = {}
  self.action_window = {}
  self.reward_window = {}

  if self.experience_count >= self.sampleN then
    for n = 1, self.sampleN do
      -- sample a random game from replay memory
      local re = self.experience[torch.random(self.gen, self.experience_count)]
      local numExp = #re
      local states = torch.Tensor(numExp, self.net_inputs)
      local targets = torch.Tensor(numExp, self.net_outputs)
      for n = 1, numExp do
        local e = re[n]
        local state0 = e[1]:typeAs(torch.FloatTensor())
        local action0 = e[2][1]
        local reward0 = e[3]
        local state1 = e[4]:typeAs(torch.FloatTensor())
        -- start training
        local all_outputs = self.target_net:forward(state0)
        states[n] = state0
        targets[n] = all_outputs:clone()
        if n == numExp then -- if terminal state
          local qmax = reward0
          targets[n][action0] = qmax
        else
          local best_action = self:policy(state1)
          local qmax = reward0 + self.gamma * best_action.value
          targets[n][action0] = qmax
          if qmax > 1 then
            print(qmax)
          end
        end
      end
      self:computeGradient(states, targets)
    end
    -- update target network every few learning steps
    if self.age % self.tau == 0 then
      self.target_net = self.net:clone()
      self.target_net:evaluate()
    end
  end


  -- epsilon annealing
  if self.epsilon > self.epsilon_min then
    self.epsilon = self.epsilon - self.epsilon/self.annealing_factor
  end

end

function AI_Player:resetPlayer(LPawn, NPawn1, NPawn2)
  self.LPawn = LPawn
  self.NPawn1 = NPawn1
  self.NPawn2 = NPawn2
end

-- get available moves for the player for the current board state
function AI_Player:getAvailMoves()
  self.legalActions = self:getLegalActions()
  return #self.legalActions
end


-- make move --
function AI_Player:play()
  -- current state
  local state = {}
  for i = 1,4 do
    state[i] = {}
    for j = 1,4 do
      state[i][j] = board:getBoard()[i][j].id
    end
  end
  state = convert2DArrTo1D(state) -- convert 2D board state to 1D
  -- NN decides on an action (a0) given the current board state
  local action
  repeat
    action = self:forward(state)
  until action <= #self.legalActions
  -- add [state,action] pair into the time window
  self:addState(state)
  self:addAction(action)
  -- reward for action
  self:addReward(self.REWARD_FOR_MOVE, false)
  local chosenAction = self.legalActions[action]
  self:pickUpPawn(self.LPawn) -- pick up L-Pawn from the board
  self.LPawn.pawnPos = chosenAction.LPawnPos -- set chosen L-Pawn position as current
  self:placePawn(self.LPawn) -- place L-Pawn on the chosen position on the board
  local NPawn
  if chosenAction.NPawnChoice == 1 then
    NPawn = self.NPawn1
  else
    NPawn = self.NPawn2
  end
  self:pickUpPawn(NPawn)
  NPawn.pawnPos = chosenAction.NPawnPos
  self:placePawn(NPawn)
end

-- pick up pawn from board --
function AI_Player:pickUpPawn(pawn)
  local board = board:getBoard()
  local i = 1
  while pawn.pawnPos[i] do
    local x, y = pawn.pawnPos[i][1], pawn.pawnPos[i][2]
    board[x][y].id = 0
    board[x][y].color = {255,255,255}
    i = i + 1
  end
end

-- place pawn on board --
function AI_Player:placePawn(pawn)
  local board = board:getBoard()
  local i = 1
  while pawn.pawnPos[i] do
    local x, y = pawn.pawnPos[i][1], pawn.pawnPos[i][2]
    board[x][y].id = pawn.pawnId
    board[x][y].color = pawn.pawnColor
    i = i + 1
  end
end

function AI_Player:getLegalActions()

  local legalActions = {}

  local function initAction()
    local LPawnPos = {}
    for i = 1,4 do
      LPawnPos[i] = {}
      for j = 1,2 do
        LPawnPos[i][j] = 0
      end
    end
    local NPawnChoice = 0
    local NPawnPos = {}
    NPawnPos[1] = {}
    for j = 1,2 do
      NPawnPos[1][j] = 0
    end
    local action = {LPawnPos = LPawnPos, NPawnChoice = NPawnChoice, NPawnPos = NPawnPos}
    return action
  end

  -- start with "L" orientation of the L-Pawn
  for i = 1,2 do
    for j = 1,3 do
      for k = 1,2 do -- for each N-Pawn choice
        for m = 1,4 do
          for n = 1,4 do
            local action = initAction()
            action.LPawnPos[1][1] = i
            action.LPawnPos[1][2] = j
            action.LPawnPos[2][1] = i + 1
            action.LPawnPos[2][2] = j
            action.LPawnPos[3][1] = i + 2
            action.LPawnPos[3][2] = j
            action.LPawnPos[4][1] = i + 2
            action.LPawnPos[4][2] = j + 1
            action.NPawnChoice = k
            action.NPawnPos[1][1] = m
            action.NPawnPos[1][2] = n
            if self:isALegalAction(action) then
              table.insert(legalActions, action)
            end
          end
      end
      end
    end
  end
  -- rotate L-Pawn clock-wise
  for i = 1,3 do
    for j = 1,2 do
      for k = 1,2 do
        for m = 1,4 do
          for n = 1,4 do
            local action = initAction()
            action.LPawnPos[1][1] = i
            action.LPawnPos[1][2] = j + 2
            action.LPawnPos[2][1] = i
            action.LPawnPos[2][2] = j + 1
            action.LPawnPos[3][1] = i
            action.LPawnPos[3][2] = j
            action.LPawnPos[4][1] = i + 1
            action.LPawnPos[4][2] = j
            action.NPawnChoice = k
            action.NPawnPos[1][1] = m
            action.NPawnPos[1][2] = n
            if self:isALegalAction(action) then
              table.insert(legalActions, action)
            end
          end
        end
      end
    end
  end
  -- rotate L-Pawn clock-wise
  for i = 1,2 do
    for j = 1,3 do
      for k = 1,2 do
        for m = 1,4 do
          for n = 1,4 do
            local action = initAction()
            action.LPawnPos[1][1] = i + 2
            action.LPawnPos[1][2] = j + 1
            action.LPawnPos[2][1] = i + 1
            action.LPawnPos[2][2] = j + 1
            action.LPawnPos[3][1] = i
            action.LPawnPos[3][2] = j + 1
            action.LPawnPos[4][1] = i
            action.LPawnPos[4][2] = j
            action.NPawnChoice = k
            action.NPawnPos[1][1] = m
            action.NPawnPos[1][2] = n
            if self:isALegalAction(action) then
              table.insert(legalActions, action)
            end
          end
        end
      end
    end
  end
  -- rotate L-Pawn clock-wise
  for i = 1,3 do
    for j = 1,2 do
      for k = 1,2 do
        for m = 1,4 do
          for n = 1,4 do
            local action = initAction()
            action.LPawnPos[1][1] = i + 1
            action.LPawnPos[1][2] = j
            action.LPawnPos[2][1] = i + 1
            action.LPawnPos[2][2] = j + 1
            action.LPawnPos[3][1] = i + 1
            action.LPawnPos[3][2] = j + 2
            action.LPawnPos[4][1] = i
            action.LPawnPos[4][2] = j + 2
            action.NPawnChoice = k
            action.NPawnPos[1][1] = m
            action.NPawnPos[1][2] = n
            if self:isALegalAction(action) then
              table.insert(legalActions, action)
            end
          end
        end
      end
    end
  end
  -- flip L-Pawn
  for i = 1,2 do
    for j = 1,3 do
      for k = 1,2 do
        for m = 1,4 do
          for n = 1,4 do
            local action = initAction()
            action.LPawnPos[1][1] = i
            action.LPawnPos[1][2] = j + 1
            action.LPawnPos[2][1] = i + 1
            action.LPawnPos[2][2] = j + 1
            action.LPawnPos[3][1] = i + 2
            action.LPawnPos[3][2] = j + 1
            action.LPawnPos[4][1] = i + 2
            action.LPawnPos[4][2] = j
            action.NPawnChoice = k
            action.NPawnPos[1][1] = m
            action.NPawnPos[1][2] = n
            if self:isALegalAction(action) then
              table.insert(legalActions, action)
            end
          end
        end
      end
    end
  end
  -- rotate clock-wise
  for i = 1,3 do
    for j = 1,2 do
      for k = 1,2 do
        for m = 1,4 do
          for n = 1,4 do
            local action = initAction()
            action.LPawnPos[1][1] = i + 1
            action.LPawnPos[1][2] = j + 2
            action.LPawnPos[2][1] = i + 1
            action.LPawnPos[2][2] = j + 1
            action.LPawnPos[3][1] = i + 1
            action.LPawnPos[3][2] = j
            action.LPawnPos[4][1] = i
            action.LPawnPos[4][2] = j
            action.NPawnChoice = k
            action.NPawnPos[1][1] = m
            action.NPawnPos[1][2] = n
            if self:isALegalAction(action) then
              table.insert(legalActions, action)
            end
          end
        end
      end
    end
  end
  -- rotate clock-wise
  for i = 1,2 do
    for j = 1,3 do
      for k = 1,2 do
        for m = 1,4 do
          for n = 1,4 do
            local action = initAction()
            action.LPawnPos[1][1] = i + 2
            action.LPawnPos[1][2] = j
            action.LPawnPos[2][1] = i + 1
            action.LPawnPos[2][2] = j
            action.LPawnPos[3][1] = i
            action.LPawnPos[3][2] = j
            action.LPawnPos[4][1] = i
            action.LPawnPos[4][2] = j + 1
            action.NPawnChoice = k
            action.NPawnPos[1][1] = m
            action.NPawnPos[1][2] = n
            if self:isALegalAction(action) then
              table.insert(legalActions, action)
            end
          end
        end
      end
    end
  end
  -- rotate clock-wise
  for i = 1,3 do
    for j = 1,2 do
      for k = 1,2 do
        for m = 1,4 do
          for n = 1,4 do
            local action = initAction()
            action.LPawnPos[1][1] = i
            action.LPawnPos[1][2] = j
            action.LPawnPos[2][1] = i
            action.LPawnPos[2][2] = j + 1
            action.LPawnPos[3][1] = i
            action.LPawnPos[3][2] = j + 2
            action.LPawnPos[4][1] = i + 1
            action.LPawnPos[4][2] = j + 2
            action.NPawnChoice = k
            action.NPawnPos[1][1] = m
            action.NPawnPos[1][2] = n
            if self:isALegalAction(action) then
              table.insert(legalActions, action)
            end
          end
        end
      end
    end
  end
  return legalActions
end

-- check if action is legal
function AI_Player:isALegalAction(action)
  local board = board:getBoard()
  -- check if an L-Pawn and N-Pawn occupy the same space
  for i = 1, 4 do
    if action.NPawnPos[1][1] == action.LPawnPos[i][1] and action.NPawnPos[1][2] == action.LPawnPos[i][2] then
      return false
    end
  end
  -- check if L-Pawn occupies the same space as another player's pawn
  local LPawnPlacementLegal = false
  local NPawnPlacementLegal = false
  local numFreeSlots, numEqualSlots = 0, 0
  for i = 1, 4 do
    local x, y = action.LPawnPos[i][1], action.LPawnPos[i][2]
    if board[x][y].id == 0 or board[x][y].id == self.LPawn.pawnId then
      numFreeSlots = numFreeSlots + 1
    end
    if board[x][y].id == self.LPawn.pawnId then
      numEqualSlots = numEqualSlots + 1
    end
  end
  if numFreeSlots == 4 and numFreeSlots > numEqualSlots then
    LPawnPlacementLegal = true
  end
  -- do the same for N-Pawn
  local numFreeSlots, numEqualSlots = 0, 0
  local x, y = action.NPawnPos[1][1], action.NPawnPos[1][2]
  local NPawnId
  if action.NPawnChoice == 1 then
    NPawnId = self.NPawn1.pawnId
  else
    NPawnId = self.NPawn2.pawnId
  end
  if board[x][y].id == 0 or board[x][y].id == NPawnId then
    numFreeSlots = numFreeSlots + 1
  end
  if board[x][y].id == NPawnId then
    numEqualSlots = numEqualSlots + 1
  end
  if numFreeSlots == 1 and numFreeSlots > numEqualSlots then
    NPawnPlacementLegal = true
  end
  if LPawnPlacementLegal and NPawnPlacementLegal then
    return true
  else
    return false
  end
end

function AI_Player:train(winner)
  if winner == self.playerId then
    self:addReward(self.REWARD_FOR_WIN, true)
    self.reward_tot = self.reward_tot + self.REWARD_FOR_WIN
  elseif winner == 0 then
    self:addReward(self.REWARD_FOR_DRAW, true)
    self.reward_tot = self.reward_tot + self.REWARD_FOR_DRAW
  else
    self:addReward(self.REWARD_FOR_LOSS, true)
    self.reward_tot = self.reward_tot + self.REWARD_FOR_LOSS
  end
  -- add terminal state to the state window
  local state = {}
  for i = 1,4 do
    state[i] = {}
    for j = 1,4 do
      state[i][j] = board:getBoard()[i][j].id
    end
  end
  state = convert2DArrTo1D(state)
  self:addState(state)
  self:backward() -- train the network
end

function AI_Player:getProgress()
  return self.reward_tot
end

function AI_Player:resetProgress()
  self.reward_tot = 0
end

return AI_Player
