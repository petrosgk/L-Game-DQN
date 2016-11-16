local board = require 'board'
local random_player = require 'random_player'
local ai_player = require 'ai_player'
local pawn = require 'pawn'

local Game = {}

local PRINT

local P1_IS_AI, P2_IS_AI
local P1_IS_LEARNING, P2_IS_LEARNING

local LPawn_P1, LPawn_P2, NPawn1, NPawn2

local moveCount_P1, moveCount_P2 = 0, 0
local winner

function Game:initPawns()
  -- initialize player and neutral pawns
  LPawn_P1 = pawn:init(nil, 'Player', 1, {0,0,255})
  LPawn_P2 = pawn:init(nil, 'Player', 2, {255,0,0})
  NPawn1 = pawn:init(nil, 'Neutral', 3, {255,255,0})
  NPawn2 = pawn:init(nil, 'Neutral', 4, {0,255,0})
  -- place Player 1's pawns on their initial positions on the board
  LPawn_P1.pawnPos[1][1], LPawn_P1.pawnPos[1][2] = 2, 2
  LPawn_P1.pawnPos[2][1], LPawn_P1.pawnPos[2][2] = 3, 2
  LPawn_P1.pawnPos[3][1], LPawn_P1.pawnPos[3][2] = 4, 2
  LPawn_P1.pawnPos[4][1], LPawn_P1.pawnPos[4][2] = 4, 3
  board:setBoard(LPawn_P1)
  -- place Player 2's pawns on their initial positions on the board
  LPawn_P2.pawnPos[1][1], LPawn_P2.pawnPos[1][2] = 3, 3
  LPawn_P2.pawnPos[2][1], LPawn_P2.pawnPos[2][2] = 2, 3
  LPawn_P2.pawnPos[3][1], LPawn_P2.pawnPos[3][2] = 1, 3
  LPawn_P2.pawnPos[4][1], LPawn_P2.pawnPos[4][2] = 1, 2
  board:setBoard(LPawn_P2)
  -- place neutral pawns on their initial positions on the board
  NPawn1.pawnPos[1][1], NPawn1.pawnPos[1][2] = 1, 1
  board:setBoard(NPawn1)
  NPawn2.pawnPos[1][1], NPawn2.pawnPos[1][2] = 4, 4
  board:setBoard(NPawn2)
end

function Game:initPlayers()
  if P1_IS_AI then
    -- initialize Player 1 as AI player
    Game.player1 = ai_player:initPlayer(nil, 1, LPawn_P1, NPawn1, NPawn2)
  else
    --initialize RNG for random player
    local genP1 = torch.Generator()
    torch.seed(genP1)
    -- initialize Player 1 as random player
    Game.player1 = random_player:initPlayer(nil, 1, LPawn_P1, NPawn1, NPawn2, genP1)
  end
  if P2_IS_AI then
    -- initialize Player 2 as AIplayer
    Game.player2 = ai_player:initPlayer(nil, 2, LPawn_P2, NPawn1, NPawn2)
  else
    --initialize RNG for random player
    local genP2 = torch.Generator()
    torch.seed(genP2)
    -- initialize Player 2 as random player
    Game.player2 = random_player:initPlayer(nil, 2, LPawn_P2, NPawn1, NPawn2, genP2)
  end
end


function Game:initGame(print, p1_is_ai, p2_is_ai, p1_is_learning, p2_is_learning)
  PRINT = print
  P1_IS_AI = p1_is_ai
  P2_IS_AI = p2_is_ai
  P1_IS_LEARNING = p1_is_learning
  P2_IS_LEARNING = p2_is_learning
  -- initialize the board
  board:initBoard()
  -- initialize the pawns
  self:initPawns()
  -- initialize the players
  self:initPlayers()
end

function Game:startGame()
  if PRINT then
    posix.unistd.sleep(1)
    board:printBoard()
  end
  while Game.player1:getAvailMoves() > 0 and Game.player2:getAvailMoves() > 0 do
    Game.player1:play()
    moveCount_P1 = moveCount_P1 + 1
    if PRINT then
      print('Player 1 move: ')
      posix.unistd.sleep(1)
      board:printBoard()
    end
    if Game.player2:getAvailMoves() > 0 then
      Game.player2:play()
      moveCount_P2 = moveCount_P2 + 1
      if PRINT then
        print('Player 2 move: ')
        posix.unistd.sleep(1)
        board:printBoard()
      end
    else
      break
    end
  end
  if Game.player1:getAvailMoves() > 0 and Game.player2:getAvailMoves() == 0 then
    winner = Game.player1.playerId
    self:endGame()
  elseif Game.player1:getAvailMoves() == 0 and Game.player2:getAvailMoves() > 0 then
    winner = Game.player2.playerId
    self:endGame()
  else
    winner = 0
    self:endGame()
  end
end

function Game:endGame()
  if PRINT == true then
    print('Final state\n')
    board:printBoard()
  end
  if PRINT then
    if winner == Game.player1.playerId then
      print('Player 1' .. ' wins in ' .. moveCount_P1 .. ' moves')
    elseif winner == Game.player2.playerId then
      print('Player 2' .. ' wins in ' .. moveCount_P2 .. ' moves')
    else
      print('Draw!')
    end
    print('\n')
  end
  if P1_IS_AI and P1_IS_LEARNING then
    Game.player1:train(winner)
  end
  if P2_IS_AI and P2_IS_LEARNING then
    Game.player2:train(winner)
  end
  self:resetGame()
end

function Game:resetGame()
  board:resetBoard()
  self:initPawns()
  Game.player1:resetPlayer(LPawn_P1, NPawn1, NPawn2)
  Game.player2:resetPlayer(LPawn_P2, NPawn1, NPawn2)
  moveCount_P1, moveCount_P2 = 0, 0
end

function Game:getWinner()
  return winner
end

function Game:getAgentProgress()
  if P1_IS_LEARNING and not (P1_IS_LEARNING and P2_IS_LEARNING) then
    local reward_tot
    reward_tot = Game.player1:getProgress()
    Game.player1:resetProgress()
    return reward_tot
  end
  if P2_IS_LEARNING and not (P1_IS_LEARNING and P2_IS_LEARNING) then
    local reward_tot
    reward_tot = Game.player2:getProgress()
    Game.player2:resetProgress()
    return reward_tot
  end
  if P1_IS_LEARNING and P2_IS_LEARNING then
    local reward_tot_p1, reward_tot_p2
    reward_tot_p1 = Game.player1:getProgress()
    Game.player1:resetProgress()
    reward_tot_p2 = Game.player2:getProgress()
    Game.player2:resetProgress()
    return reward_tot_p1, reward_tot_p2
  end
end

return Game
