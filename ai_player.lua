local board = require 'board'
local DQN = require 'DQN/deepqlearn'
require 'utils'

local USE_GPU = false

-- agent reward parameters
local REWARD_FOR_LOSS = -1
local REWARD_FOR_DRAW = 0
local REWARD_FOR_WIN = 1

-- track cumulative reward of agent
local reward_tot = 0

local legalActions -- legal moves for the current state

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
  -- initialize net
  DQN.init(16, 128)
  return o
end

function AI_Player:resetPlayer(LPawn, NPawn1, NPawn2)
  self.LPawn = LPawn
  self.NPawn1 = NPawn1
  self.NPawn2 = NPawn2
end

-- get available moves for the player for the current board state
function AI_Player:getAvailMoves()
  legalActions = self:getLegalActions()
  return #legalActions
end


-- make move --
function AI_Player:play()
  -- current state
  local state = deepcopy(board:getBoard()) -- make a deep copy
  state = convert2DArrTo1D(state) -- convert 2D board state to 1D
  -- NN decides on an action given the current board state
  local action
  repeat
    action = DQN.forward(state)
  until action <= #legalActions
  -- add [state,action] pair into the time window
  DQN.addState(state)
  DQN.addAction(action)
  local chosenAction = legalActions[action]
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
    board[x][y] = 0
    i = i + 1
  end
end

-- place pawn on board --
function AI_Player:placePawn(pawn)
  local board = board:getBoard()
  local i = 1
  while pawn.pawnPos[i] do
    local x, y = pawn.pawnPos[i][1], pawn.pawnPos[i][2]
    board[x][y] = pawn.pawnId
    i = i + 1
  end
end

function AI_Player:getLegalActions()

  local legalActions = {}

  function initAction()
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
    if board[x][y] == 0 or board[x][y] == self.LPawn.pawnId then
      numFreeSlots = numFreeSlots + 1
    end
    if board[x][y] == self.LPawn.pawnId then
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
  if board[x][y] == 0 or board[x][y] == NPawnId then
    numFreeSlots = numFreeSlots + 1
  end
  if board[x][y] == NPawnId then
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

function AI_Player:updateReward(winner)
  if winner == 2 then
    DQN.addReward(REWARD_FOR_WIN)
    reward_tot = reward_tot + REWARD_FOR_WIN
  elseif winner == 1 then
    DQN.addReward(REWARD_FOR_LOSS)
    reward_tot = reward_tot + REWARD_FOR_LOSS
  else
    DQN.addReward(REWARD_FOR_DRAW)
    reward_tot = reward_tot + REWARD_FOR_DRAW
  end
  -- add the terminal state (end of game)
  local state = deepcopy(board:getBoard())
  state = convert2DArrTo1D(state)
  DQN.addState(state)
  DQN.backward() -- update the network
end

function AI_Player:getProgress()
  return reward_tot
end

function AI_Player:resetProgress()
  reward_tot = 0
end

return AI_Player
