local Board = {}

local board

-- create and initialize game board
function Board:initBoard()
	board = {}
	for i = 1,4 do
		board[i] = {}
		for j = 1,4 do
			board[i][j] = 0
		end
	end
end

-- alter board state
function Board:setBoard(pawn)
	local i = 1
	while pawn.pawnPos[i] do
		local x, y = pawn.pawnPos[i][1], pawn.pawnPos[i][2]
		board[x][y] = pawn.pawnId
		i = i + 1
	end
end

function Board:getBoard()
	return board
end

function Board:printBoard()
	for i = 1, 4 do
		print(board[i][1] .. ' ' .. board[i][2] .. ' ' .. board[i][3] .. ' ' .. board[i][4])
	end
	print('\n')
end

function Board:resetBoard()
	for i = 1,4 do
		for j = 1,4 do
			board[i][j] = 0
		end
	end
end

return Board