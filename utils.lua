local Utils = {}

function deepcopy(orig)
	local orig_type = type(orig)
	local copy
	if orig_type == 'table' then
		copy = {}
		for orig_key, orig_value in next, orig, nil do
			copy[deepcopy(orig_key)] = deepcopy(orig_value)
		end
		setmetatable(copy, deepcopy(getmetatable(orig)))
	else -- number, string, boolean, etc
		copy = orig
	end
	return copy
end

function convert2DArrTo1D(arr)
	local newArr = {}
	for i = 1, #arr do
		for j = 1, #arr[1] do
			newArr[i * #arr[1] + j - #arr[1]] = arr[i][j]
		end
	end
	return newArr
end

function randf(gen, s, e)
	return (torch.random(gen, 0,(e-s)*9999)/10000) + s;
end

return Utils