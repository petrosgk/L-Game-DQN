local board = require 'board'
local random_player = require 'random_player'
local ai_player = require 'ai_player'
local pawn = require 'pawn'

local Game = {}

local PRINT

local USE_AI
local HUMAN

local LPawn_P1, LPawn_P2, NPawn1, NPawn2
local player1, player2

local moveCount_P1, moveCount_P2 = 0, 0
local winner

function Game:initPawns()
  -- initialize player and neutral pawns
  LPawn_P1 = pawn:init(nil, 'Player', 1)
  LPawn_P2 = pawn:init(nil, 'Player', 2)
  NPawn1 = pawn:init(nil, 'Neutral', 3)
  NPawn2 = pawn:init(nil, 'Neutral', 4)
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
  --initialize RNG for random player
  local genP1 = torch.Generator()
  torch.seed(genP1)
  -- initialize Player 1
  player1 = random_player:initPlayer(nil, 1, LPawn_P1, NPawn1, NPawn2, genP1)
  -- initialize Player 2
  if USE_AI then
    player2 = ai_player:initPlayer(nil, 2, LPawn_P2, NPawn1, NPawn2)
  else
    --initialize RNG for random player 2
    local genP2 = torch.Generator()
    torch.seed(genP2)
    player2 = random_player:initPlayer(nil, 2, LPawn_P2, NPawn1, NPawn2, genP2)
  end
end


function Game:initGame(print, use_ai, human)
  PRINT = print
  USE_AI = use_ai
  HUMAN = human
  -- initialize the board
  board:initBoard()
  -- initialize the pawns
  self:initPawns()
  -- initialize the players
  self:initPlayers()
end

function Game:startGame()
  if PRINT then
    board:printBoard()
  end
  local P1_availMoves, P2_availMoves -- available moves for each player
  P1_availMoves = player1:getAvailMoves()
  if P1_availMoves > 0 then
    player1:play()
    moveCount_P1 = moveCount_P1 + 1
    if PRINT then
      print('Player 1 move: ')
      board:printBoard()
    end
  end
  P2_availMoves = player2:getAvailMoves()
  if P2_availMoves > 0 then
    player2:play()
    moveCount_P2 = moveCount_P2 + 1
    if PRINT then
      print('Player 2 move: ')
      board:printBoard()
    end
  end
  while P1_availMoves > 0 and P2_availMoves > 0 do
    P1_availMoves = player1:getAvailMoves()
    if P1_availMoves > 0 then
      player1:play()
      moveCount_P1 = moveCount_P1 + 1
      if PRINT then
        print('Player 1 move: ')
        board:printBoard()
      end
    end
    P2_availMoves = player2:getAvailMoves()
    if P2_availMoves > 0 and P1_availMoves > 0  then
      player2:play()
      moveCount_P2 = moveCount_P2 + 1
      if PRINT then
        print('Player 2 move: ')
        board:printBoard()
      end
    end
  end
  if P1_availMoves > 0 and P2_availMoves == 0 then
    winner = player1.playerId
    self:endGame()
  elseif P1_availMoves == 0 and P2_availMoves > 0 then
    winner = player2.playerId
    self:endGame()
  else
    winner = nil
    self:endGame()
  end
end

function Game:endGame()
  if PRINT == true then
    print('Final state\n')
    board:printBoard()
  end
  if PRINT then
    if winner == player1.playerId then
      print('Player 1' .. ' wins in ' .. moveCount_P1 .. ' moves')
    elseif winner == player2.playerId then
      print('Player 2' .. ' wins in ' .. moveCount_P2 .. ' moves')
    else
      print('Draw!')
    end
    print('\n')
  end
  if USE_AI then
    player2:updateReward(winner)
  end
  self:resetGame()
end

function Game:resetGame()
  board:resetBoard()
  self:initPawns()
  player1:resetPlayer(LPawn_P1, NPawn1, NPawn2)
  player2:resetPlayer(LPawn_P2, NPawn1, NPawn2)
  moveCount_P1, moveCount_P2 = 0, 0
end

function Game:getWinner()
  return winner
end

function Game:getAgentProgress()
  local reward_tot = player2:getProgress()
  player2:resetProgress()
  return reward_tot
end

return Game
