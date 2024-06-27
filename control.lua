function printError(s)
	game.print("FUNKED ORE ERROR: "..s)
end

------------------------------------------------------------------------
--- FUNCTIONS FOR PARSING THE MIX STRING.

local oreAliases = {
	oil = "crude-oil",

	-- IR3: No need for anything custom. New ores with names already handled fine: tin, gold.
	-- Also: fossil-gas-fissure, sulphur-gas-fissure (for sour gas), dirty-steam-fissure (for polluted steam fissures).
	-- Not rubber trees, those are trees, not resources.

	-- Bob's ores: No changes needed for bauxite, tin, quartz, nickel, gold, zinc, sulfur, silver, tungsten, thorium.
	cobaltite = "cobalt-ore",
	galena = "lead-ore",
	gemstones = "gem-ore",
	gemstone = "gem-ore",
	groundwater = "ground-water",
	lithiawater = "lithia-water",
	titanium = "rutile-ore",
	-- ["titanium-ore"] = "rutile-ore", -- not adding, in case some other mod adds titanium-ore.

	-- Angel's ores:
	saphirite = "angels-ore1",
	jivolite = "angels-ore2",
	stiratite = "angels-ore3",
	crotinnium = "angels-ore4",
	rubyte = "angels-ore5",
	bobmonium = "angels-ore6",
	["infinite-saphirite"] = "infinite-angels-ore1",
	["infinite-jivolite"] = "infinite-angels-ore2",
	["infinite-stiratite"] = "infinite-angels-ore3",
	["infinite-crotinnium"] = "infinite-angels-ore4",
	["infinite-rubyte"] = "infinite-angels-ore5",
	["infinite-bobmonium"] = "infinite-angels-ore6",
	fissure = "angels-fissure",
	gaswell = "angels-natural-gas",
	oilwell = "crude-oil",
}
function getRealOreName(ore)
	-- Returns the internal name for an ore, given a reasonable alias.
	-- For example, given "iron", returns "iron-ore", because "iron" doesn't exist.
	-- Returns nil if ore not found.
	if ore == "nothing" then return ore end -- Special value.
	if game.entity_prototypes[ore] then
		return ore
	elseif game.entity_prototypes[ore.."-ore"] then
		return ore.."-ore"
	elseif oreAliases[ore] ~= nil and game.entity_prototypes[oreAliases[ore]] then
		return oreAliases[ore]
	end
	printError("Ore does not exist: "..ore)
	return nil
end

function parseMix(s)
	-- Maps an ore mix string like "coal+3stone" to a structure like {{"coal":1, "stone":3, "total weight":4}}.
	-- Returns nil on error.
	local mix = {}
	local totalWeight = 0 -- sum of all the given weights, to make random choices easier later.
	for optionCountStr, optionOre in string.gmatch(s, '(%d*) *([^ %d\\+][^\\+]*)') do
		optionOre = getRealOreName(optionOre)
		if optionOre == nil then return nil end
		local optionCountInt = 1
		if optionCountStr ~= "" then optionCountInt = tonumber(optionCountStr) or 0 end
		mix[optionOre] = optionCountInt
		totalWeight = totalWeight + optionCountInt
	end
	mix.totalWeight = totalWeight
	return mix
end

function parseMixOptions(s, extraArgs)
	-- Maps an ore mix options string like "coal+3stone/iron/iron+copper" to a list of those 3 alternatives.
	-- Returns nil on error.
	local mixOptions = {}
	for mix in string.gmatch(s, '([^/]+)') do
		local parsedMix = parseMix(mix)
		if parsedMix == nil then return nil end
		for key, value in pairs(extraArgs) do
			parsedMix[key] = value
		end
		table.insert(mixOptions, parsedMix)
	end
	return mixOptions
end

function parseExtraArg(s)
	-- Maps something like ">50" to {minDist=50}.
	-- Returns nil on error.
	if s:sub(1, 1) == ">" then
		return {minDist=tonumber(s:sub(2))}
	elseif s:sub(1, 1) == "<" then
		return {maxDist=tonumber(s:sub(2))}
	elseif s:sub(1, 1) == "%" then
		local modBy, op, modThreshold = s:match('^%%(%d+)([<>])(%d+)$')
		if op == "<" then
			return {modBy=tonumber(modBy), modLessThan=tonumber(modThreshold)}
		else
			return {modBy=tonumber(modBy), modGreaterThan=tonumber(modThreshold)}
		end
	end
end

function parseExtraArgs(extraArgStrs)
	-- Maps something like {">50", "<100"} to {minDist=50, maxDist=100}.
	-- Returns nil on error.
	local parsedExtraArgs = {}
	if extraArgStrs == nil then return nil end
	if #extraArgStrs == 0 then return {} end
	for _, extraArgStr in pairs(extraArgStrs) do
		local parsedArg = parseExtraArg(extraArgStr)
		if parsedArg == nil then
			printError("Could not parse extra arg: "..extraArgStr)
			return nil
		end
		for key, value in pairs(parsedArg) do
			parsedExtraArgs[key] = value
		end
	end
	return parsedExtraArgs
end

function addOreToMixesRule(oreToBeTransformed, extraArgStrs, mixOptionsStr)
	-- Adds a rule like "coal(>50)=>stone+iron" when given args "coal", {">50"}, and "stone+iron".
	-- Returns true if there was an error, else returns false.
	oreToBeTransformed = getRealOreName(oreToBeTransformed)
	if oreToBeTransformed == nil then return true end
	local extraArgs = parseExtraArgs(extraArgStrs)
	if extraArgs == nil then return true end
	local mixOptions = parseMixOptions(mixOptionsStr, extraArgs)
	if mixOptions == nil then return true end
	if global.parsedTransforms[oreToBeTransformed] == nil then
		global.parsedTransforms[oreToBeTransformed] = {}
	end
	for _, mixOption in pairs(mixOptions) do
		table.insert(global.parsedTransforms[oreToBeTransformed], mixOption)
	end
	return false
end

function reparseTransforms(s)
	global.parsedTransforms = {}
	for oreAndExtraArgs, mixOptionsStr in string.gmatch(s, '([^&]+)=>([^&]*)') do
		-- parse OreAndExtraArgs like "coal(>50)" into oreToBeTransformed = "coal" and extraArgStr = "(>50)".
		local oreToBeTransformed, extraArgStr = oreAndExtraArgs:match('^([^(]+)(.*)$')
		-- Split a string like extraArgStr "(>50)(<100)" into a list like {">50", "<100"}.
		local extraArgStrs = {}
		if extraArgStr ~= nil then
			for extraArg in string.gmatch(extraArgStr, '%(([^%(]+)%)') do
				table.insert(extraArgStrs, extraArg)
			end
		end
		local hasError = addOreToMixesRule(oreToBeTransformed, extraArgStrs, mixOptionsStr)
		if hasError then
			global.parsedTransforms = {}
			break
		end

	end
	log("Funked Ore re-parsed transforms: " .. game.table_to_json(global.parsedTransforms))
	--game.print("Funked Ore re-parsed transforms: " .. game.table_to_json(global.parsedTransforms))
end

function refreshTransforms()
	-- Checks if the transform string setting has been changed, and if so, re-parses it.
	-- Players would probably be fine with making it a startup setting that gets parsed once;
	-- but I want it to be "hot-reloadable" for convenient testing while I write this mod.
	local transformString = settings.global["FunkedOre-transform-string"].value
	transformString = transformString:gsub('%s+', '') -- Remove all spaces.
	if transformString ~= global.lastParsedTransformString then
		reparseTransforms(transformString)
		global.lastParsedTransformString = transformString
	end
end

------------------------------------------------------------------------
--- FUNCTIONS TO TRANSFORM ORES USING THE PARSED RULES

function changeOneOreEntity(resourceEntity, newOre, surface)
	if newOre ~= "nothing" then
		surface.create_entity {name=newOre, position=resourceEntity.position, amount=resourceEntity.amount}
	end
	resourceEntity.destroy()
end

function distance(a, b)
	local dx = a.x - b.x
	local dy = a.y - b.y
	return math.sqrt(dx*dx + dy*dy)
end

function createControlPoint(resourceEntity, chosenMix)
	log("Funked Ore created control point for "..resourceEntity.name.." at "..resourceEntity.position.x..","..resourceEntity.position.y.." with mix "..game.table_to_json(chosenMix))
	-- Control points are dicts with x, y, mix.
	local newControlPoint = {x=resourceEntity.position.x, y=resourceEntity.position.y, mix=chosenMix}
	table.insert(global.controlPoints[resourceEntity.name], newControlPoint)
end

function findCreateControlPoint(resourceEntity, mixOptions, distToOrigin)
	-- Finds closest control point. If none are close enough, creates a new one.
	-- If one is close enough, but still some distance away, creates a new control point with the same mix, in order to influence the rest of that ore patch.
	-- Returns the mix of the closest control point, or of the newly created control point.
	if global.controlPoints == nil then
		global.controlPoints = {[resourceEntity.name] = {}}
	end
	if global.controlPoints[resourceEntity.name] == nil then
		global.controlPoints[resourceEntity.name] = {}
	end

	local oreControlPoints = global.controlPoints[resourceEntity.name]

	local closestControlPoint = nil
	local distToClosestControlPoint = nil
	for i = 0, #oreControlPoints - 1 do
		-- We iterate through them starting from the end, since that was created most recently, so most likely to be nearby, triggering early stopping which saves time.
		local thisControlPoint = oreControlPoints[#oreControlPoints - i]
		if mixOptionAppliesAtDist(thisControlPoint.mix, distToOrigin) then
			local distEntToControlPoint = distance(thisControlPoint, resourceEntity.position)
			if distEntToControlPoint <= settings.global["FunkedOre-control-point-early-stop-dist"].value then
				closestControlPoint = thisControlPoint
				distToClosestControlPoint = distEntToControlPoint
				break
			end
			if (closestControlPoint == nil) or (distToClosestControlPoint > distEntToControlPoint) then
				closestControlPoint = thisControlPoint
				distToClosestControlPoint = distEntToControlPoint
			end
		end
	end

	if closestControlPoint == nil then
		local chosenMix = mixOptions[math.random(1, #mixOptions)]
		createControlPoint(resourceEntity, chosenMix)
		return chosenMix
	end

	-- If closest control point is out of reach, make a new one.
	if distToClosestControlPoint > settings.global["FunkedOre-control-point-reach-dist"].value then
		local chosenMix = mixOptions[math.random(1, #mixOptions)]
		createControlPoint(resourceEntity, chosenMix)
		return chosenMix
	end

	-- Reproduce control point if it's far enough away
	if distToClosestControlPoint > settings.global["FunkedOre-control-point-reproduce-after-dist"].value then
		createControlPoint(resourceEntity, closestControlPoint.mix)
	end

	return closestControlPoint.mix
end

function mixOptionAppliesAtDist(mixOption, dist)
	-- Whenever user types "<", we interpret that instead as "<="; but ">" stays ">".
	-- This is to prevent off-by-one errors when the user makes multiple rules like ">50" and "<50".
	if mixOption.minDist ~= nil and dist <= mixOption.minDist then
		return false
	end
	if mixOption.maxDist ~= nil and dist > mixOption.maxDist then
		return false
	end
	if mixOption.modBy ~= nil then
		local moddedDist = dist % mixOption.modBy
		if mixOption.modLessThan ~= nil then
			if moddedDist > mixOption.modLessThan then
				return false
			end
		end
		if mixOption.modGreaterThan ~= nil then
			if moddedDist <= mixOption.modGreaterThan then
				return false
			end
		end
	end
	return true
end

function getMixOptions(resourceEntity, distToOrigin)
	local mixOptionsForOre = global.parsedTransforms[resourceEntity.name]
	if mixOptionsForOre == nil then return {} end -- No transforms specified for this ore.
	local result = {}
	-- TODO write a filter() higher-order function for this.
	for _, mixOption in pairs(mixOptionsForOre) do
		if mixOptionAppliesAtDist(mixOption, distToOrigin) then
			table.insert(result, mixOption)
		end
	end
	return result
end

function findOrDecideLocalMix(resourceEntity)
	local distToOrigin = distance(resourceEntity.position, {x=0, y=0})
	local mixOptions = getMixOptions(resourceEntity, distToOrigin)
	if #mixOptions == 0 then return nil end
	if #mixOptions == 1 then return mixOptions[1] end
	local chosenMix = findCreateControlPoint(resourceEntity, mixOptions, distToOrigin)
	return chosenMix
end

local reservedKeywords = {minDist=true, maxDist=true, totalWeight=true, modBy=true, modLessThan=true, modGreaterThan=true}
function pickNewOre(mix)
	-- Given a mix like {coal=1, stone=1, totalWeight=2, minDist=100}, will return either "coal" or "stone" with equal probability.
	if table_size(mix) == 0 then return "nothing" end
	if mix.totalWeight == 0 then return "nothing" end
	local r = math.random(1, mix.totalWeight)
	for ore, weight in pairs(mix) do
		if reservedKeywords[ore] == nil then
			r = r - weight
			if r <= 0 then
				return ore
			end
		end
	end
	printError("Random choice code or parsing code is broken.")
end

function considerChangingOreEntity(resourceEntity, surface)
	local mix = findOrDecideLocalMix(resourceEntity)
	if mix == nil then return end
	local newOre = pickNewOre(mix)
	changeOneOreEntity(resourceEntity, newOre, surface)
end

function transformChunk(event)
	refreshTransforms()
	local surface = event.surface
	local resourceEntities = surface.find_entities_filtered {type="resource", area=event.area}
	for _,resourceEntity in pairs(resourceEntities) do
		considerChangingOreEntity(resourceEntity, surface)
	end
end

script.on_event(defines.events.on_chunk_generated, transformChunk)