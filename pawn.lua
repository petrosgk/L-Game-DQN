local Pawn = {}

function Pawn:init(o, pawnType, pawnId)
	o = o or {}
	setmetatable(o, self)
	self.__index = self
	if pawnType == 'Player' then
		-- initialize player pawn
		o.pawnId = pawnId
		o.pawnPos = {}
		for i = 1,4 do
			o.pawnPos[i] = {}
			for j = 1,2 do
				o.pawnPos[i][j] = 0
			end
		end
	elseif pawnType == 'Neutral' then
		-- initialize neutral pawn
		o.pawnId = pawnId
		o.pawnPos = {}
		o.pawnPos[1] = {}
		for j = 1,2 do
			o.pawnPos[1][j] = 0
		end
	end
	return o
end

return Pawn