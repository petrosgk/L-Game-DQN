require 'xlua'
local game = require 'game'
local DQN = require 'DQN/deepqlearn'

local MAX_NUMBER_OF_GAMES = 40000  -- max number of games to run
local CHECKPOINT = 500 -- check progress every specified number of games

local P1_winCount_final, P2_winCount_final, drawCount_final = 0, 0, 0

local USE_AI = true
local LEARNING = false -- training or validating
local CONTINUE = false -- if continuing previous training

local PRINT = false

game:initGame(PRINT, USE_AI)

io.write(string.format('\n'))

if USE_AI then
  if LEARNING then
    -- learning phase
    local P1_winCount, P2_winCount, drawCount = 0, 0, 0
    DQN.learning = true
    -- if continuing previous training
    if CONTINUE then
      -- load the partially trained model
      local t_net = torch.load('learned_model.dat')
      DQN.loadModel(t_net)
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
        torch.save('learned_model.dat', DQN.net, 'binary')
      end
    end
  else
    io.write(string.format('Evaluating...\n\n'))
    -- testing phase
    MAX_NUMBER_OF_GAMES = 1000
    -- load the trained model
    local t_net = torch.load('learned_model.dat')
    DQN.learning = false
    DQN.loadModel(t_net)
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
