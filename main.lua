require 'xlua'
require 'image'
require 'posix'
local game = require 'game'

local MAX_NUMBER_OF_GAMES = 100000  -- max number of games to run
local CHECKPOINT = 1000 -- check progress every specified number of games

local P1_winCount_final, P2_winCount_final, drawCount_final = 0, 0, 0

local P1_IS_AI, P2_IS_AI = true, false
local P1_IS_LEARNING, P2_IS_LEARNING = false, false -- training or validating
local P1_CONTINUE, P2_CONTINUE = false, false -- if loading a previously trained network

local PRINT = false

torch.setdefaulttensortype('torch.FloatTensor')

game:initGame(PRINT, P1_IS_AI, P2_IS_AI, P1_IS_LEARNING, P2_IS_LEARNING)

io.write(string.format('\n'))

if (P1_IS_AI or P2_IS_AI) and not (P1_IS_AI and P2_IS_AI) then
  if P1_IS_LEARNING or P2_IS_LEARNING then
    -- learning phase
    local P1_winCount, P2_winCount, drawCount = 0, 0, 0
    if P1_IS_LEARNING then
      game.player1.learning = true
    else
      game.player2.learning = true
    end
    -- if continuing previous training
    if P1_CONTINUE or P2_CONTINUE then
      -- load the partially trained model
      if P1_CONTINUE then
        local t_net = torch.load('learned_model_p1.dat')
        game.player1:loadModel(t_net)
      else
        local t_net = torch.load('learned_model_p2.dat')
        game.player2:loadModel(t_net)
      end
    end
    for i = 1, MAX_NUMBER_OF_GAMES do
      -- run specified number of games
      game:startGame()
      xlua.progress(i, MAX_NUMBER_OF_GAMES)
      if game:getWinner() == 1 then
        P1_winCount = P1_winCount + 1
        P1_winCount_final = P1_winCount_final + 1
      elseif game:getWinner() == 2 then
        P2_winCount = P2_winCount + 1
        P2_winCount_final = P2_winCount_final + 1
      else
        drawCount = drawCount + 1
        drawCount_final = drawCount_final + 1
      end
      if i % CHECKPOINT == 0 then
        if i ~= MAX_NUMBER_OF_GAMES then
          io.write(string.format('\n'))
        end
        io.write(string.format('\nFor last %d games:\n', CHECKPOINT))
        local P1_winPercent = (P1_winCount / CHECKPOINT) * 100
        local P2_winPercent = (P2_winCount / CHECKPOINT) * 100
        local drawPercent = (drawCount / CHECKPOINT) * 100
        io.write(string.format('Player 1 win %%: %.1f\n', P1_winPercent))
        io.write(string.format('Player 2 win %%: %.1f\n', P2_winPercent))
        io.write(string.format('Draw %%: %.1f\n', drawPercent))
        io.write(string.format('Agent total reward: %d\n', game:getAgentProgress()))
        io.write(string.format('\n'))
        P1_winCount, P2_winCount, drawCount = 0, 0, 0
        -- save progress
        if P1_IS_LEARNING then
          torch.save('learned_model_p1.dat', game.player1.net, 'binary')
        else
          torch.save('learned_model_p2.dat', game.player2.net, 'binary')
        end
      end
    end
  else
    io.write(string.format('Evaluating...\n\n'))
    -- testing phase
    MAX_NUMBER_OF_GAMES = 5000
    -- load the trained model
    if P1_IS_AI then
      local t_net = torch.load('learned_model_p1.dat')
      game.player1.learning = false
      game.player1:loadModel(t_net)
    else
      local t_net = torch.load('learned_model_p2.dat')
      game.player2.learning = false
      game.player2:loadModel(t_net)
    end
    for i = 1, MAX_NUMBER_OF_GAMES do
      -- run specified number of games
      game:startGame()
      xlua.progress(i, MAX_NUMBER_OF_GAMES)
      if game:getWinner() == 1 then
        P1_winCount_final = P1_winCount_final + 1
      elseif game:getWinner() == 2 then
        P2_winCount_final = P2_winCount_final + 1
      else
        drawCount_final = drawCount_final + 1
      end
    end
  end
elseif P1_IS_AI and P2_IS_AI then
  local P1_winCount, P2_winCount, drawCount = 0, 0, 0
  if P1_IS_LEARNING then
    game.player1.learning = true
    game.player2.learning = false
    local t_net = torch.load('learned_model_p2.dat')
    game.player2:loadModel(t_net)
    game.player2.epsilon = 0.01
  end
  if P2_IS_LEARNING then
    game.player2.learning = true
    game.player1.learning = false
    local t_net = torch.load('learned_model_p1.dat')
    game.player1:loadModel(t_net)
    game.player1.epsilon = 0.01
  end
  -- if continuing previous training
  if P1_CONTINUE or P2_CONTINUE then
    -- load the partially trained model
    if P1_CONTINUE then
      local t_net = torch.load('learned_model_p1.dat')
      game.player1:loadModel(t_net)
    end
    if P2_CONTINUE then
      local t_net = torch.load('learned_model_p2.dat')
      game.player2:loadModel(t_net)
    end
  end
  for i = 1, MAX_NUMBER_OF_GAMES do
    -- run specified number of games
    game:startGame()
    xlua.progress(i, MAX_NUMBER_OF_GAMES)
    if game:getWinner() == 1 then
      P1_winCount = P1_winCount + 1
      P1_winCount_final = P1_winCount_final + 1
    elseif game:getWinner() == 2 then
      P2_winCount = P2_winCount + 1
      P2_winCount_final = P2_winCount_final + 1
    else
      drawCount = drawCount + 1
      drawCount_final = drawCount_final + 1
    end
    if i % CHECKPOINT == 0 then
      if i ~= MAX_NUMBER_OF_GAMES then
        io.write(string.format('\n'))
      end
      io.write(string.format('\nFor last %d games:\n', CHECKPOINT))
      local P1_winPercent = (P1_winCount / CHECKPOINT) * 100
      local P2_winPercent = (P2_winCount / CHECKPOINT) * 100
      local drawPercent = (drawCount / CHECKPOINT) * 100
      io.write(string.format('Player 1 win %%: %.1f\n', P1_winPercent))
      io.write(string.format('Player 2 win %%: %.1f\n', P2_winPercent))
      io.write(string.format('Draw %%: %.1f\n', drawPercent))
      if P1_IS_LEARNING and P2_IS_LEARNING then
        local reward_p1, reward_p2 = game:getAgentProgress()
        io.write(string.format('Agents total rewards: R_A1 = %d, R_A2 = %d\n', reward_p1, reward_p2))
      else
        io.write(string.format('Agent total reward: %d\n', game:getAgentProgress()))
      end
      io.write(string.format('\n'))
      P1_winCount, P2_winCount, drawCount = 0, 0, 0
      -- save progress
      if P1_IS_LEARNING then
        torch.save('learned_model_p1.dat', game.player1.net, 'binary')
      end
      if P2_IS_LEARNING then
        torch.save('learned_model_p2.dat', game.player2.net, 'binary')
      end
    end
  end
else
  -- just using random players
  for i = 1, MAX_NUMBER_OF_GAMES do
    -- run specified number of games
    game:startGame()
    xlua.progress(i, MAX_NUMBER_OF_GAMES)
    if game:getWinner() == 1 then
      P1_winCount_final = P1_winCount_final + 1
    elseif game:getWinner() == 2 then
      P2_winCount_final = P2_winCount_final + 1
    else
      drawCount_final = drawCount_final + 1
    end
  end
end

local P1_winPercent_final = (P1_winCount_final / MAX_NUMBER_OF_GAMES) * 100
local P2_winPercent_final = (P2_winCount_final / MAX_NUMBER_OF_GAMES) * 100
local drawPercent_final = (drawCount_final / MAX_NUMBER_OF_GAMES) * 100

io.write(string.format('\nResults after %d games:\n', MAX_NUMBER_OF_GAMES))
io.write(string.format('Player 1 win %%: %.1f\n', P1_winPercent_final))
io.write(string.format('Player 2 win %%: %.1f\n', P2_winPercent_final))
io.write(string.format('Draw %%: %.1f\n', drawPercent_final))
io.write(string.format('\n'))
