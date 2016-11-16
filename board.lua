local Board = {}

local board

-- create and initialize game board
function Board:initBoard()
  board = {}
  for i = 1,4 do
    board[i] = {}
    for j = 1,4 do
      board[i][j] = {id = 0, color = {255,255,255}}
    end
  end
end

-- alter board state
function Board:setBoard(pawn)
  local i = 1
  while pawn.pawnPos[i] do
    local x, y = pawn.pawnPos[i][1], pawn.pawnPos[i][2]
    board[x][y].id = pawn.pawnId
    board[x][y].color = pawn.pawnColor
    i = i + 1
  end
end

function Board:getBoard()
  return board
end

function Board:printBoard()
  for i = 1, 4 do
    print(board[i][1].id .. ' ' .. board[i][2].id .. ' ' .. board[i][3].id .. ' ' .. board[i][4].id)
  end
  print('\n')
  local board_img = {}
  for i = 1,3 do
    board_img[i] = {}
    for j = 1,4 do
      board_img[i][j] = {}
      for k = 1,4 do
        board_img[i][j][k] = 0
        board_img[i][j][k] = 0
        board_img[i][j][k] = 0
      end
    end
  end
  for j = 1,4 do
    for k = 1,4 do
      board_img[1][j][k] = board[j][k].color[1]
      board_img[2][j][k] = board[j][k].color[2]
      board_img[3][j][k] = board[j][k].color[3]
    end
  end

  board_img = torch.Tensor(board_img)
  board_img = image.scale(board_img, 128, 128, 'simple')
  image.save('board.png', board_img)
end

function Board:resetBoard()
  for i = 1,4 do
    for j = 1,4 do
      board[i][j].id = 0
      board[i][j].color = {255,255,255}
    end
  end
end

return Board
