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
	mix["total weight"] = totalWeight
	return mix
end

function parseMixOptions(s)
	-- Maps an ore mix options string like "coal+3stone/iron/iron+copper" to a list of those 3 alternatives.
	-- Returns nil on error.
	local mixOptions = {}
	for mix in string.gmatch(s, '([^/]+)') do
		local parsedMix = parseMix(mix)
		if parsedMix == nil then return nil end
		table.insert(mixOptions, parsedMix)
	end
	return mixOptions
end

function addOreToMixesRule(oreToBeTransformed, mixOptions)
	-- Adds a rule like "coal=>stone+iron" when given args "coal" and "stone+iron".
	-- Returns true if there was an error, else returns false.
	oreToBeTransformed = getRealOreName(oreToBeTransformed)
	if oreToBeTransformed == nil then return true end
	if global.parsedTransforms[oreToBeTransformed] ~= nil then
		printError("Ore appears at the start of multiple transform rules: "..oreToBeTransformed)
		return true
	end
	local mixOptions = parseMixOptions(mixOptions)
	if mixOptions == nil then return true end
	global.parsedTransforms[oreToBeTransformed] = mixOptions
	return false
end

function reparseTransforms(s)
	global.parsedTransforms = {}
	for oreToBeTransformed, mixOptions in string.gmatch(s, '([^&]+)=>([^&]*)') do
		local hasError = addOreToMixesRule(oreToBeTransformed, mixOptions)
		if hasError then
			global.parsedTransforms = {}
			break
		end
	end
	log("Funked Ore re-parsed transforms: " .. game.table_to_json(global.parsedTransforms))
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

function findCreateControlPoint(resourceEntity, mixOptions)
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
	if #oreControlPoints == 0 then
		local chosenMix = mixOptions[math.random(1, #mixOptions)]
		createControlPoint(resourceEntity, chosenMix)
		return chosenMix
	end

	local closestControlPoint = nil
	local distToClosestControlPoint = nil
	for i = 0, #oreControlPoints - 1 do
		-- We iterate through them starting from the end, since that was created most recently, so most likely to be nearby, triggering early stopping which saves time.
		local thisControlPoint = oreControlPoints[#oreControlPoints - i]
		local dist = distance(thisControlPoint, resourceEntity.position)
		if dist <= settings.global["FunkedOre-control-point-early-stop-dist"].value then
			closestControlPoint = thisControlPoint
			distToClosestControlPoint = dist
			break
		end
		if (closestControlPoint == nil) or (distToClosestControlPoint > dist) then
			closestControlPoint = thisControlPoint
			distToClosestControlPoint = dist
		end
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

function findOrDecideLocalMix(resourceEntity)
	local mixOptions = global.parsedTransforms[resourceEntity.name]
	if mixOptions == nil then return nil end -- No transforms specified for this ore.
	if #mixOptions == 1 then return mixOptions[1] end
	local chosenMix = findCreateControlPoint(resourceEntity, mixOptions)
	return chosenMix
end

function pickNewOre(mix)
	-- Given a mix like {"coal":1, "stone":1, "total weight":2}, will return either "coal" or "stone" with equal probability.
	if table_size(mix) == 0 then return "nothing" end
	if mix["total weight"] == 0 then return "nothing" end
	local r = math.random(1, mix["total weight"])
	for ore, weight in pairs(mix) do
		if ore ~= "total weight" then
			r = r - weight
			if r <= 0 then
				return ore
			end
		end
	end
	printError("Random choice code or parsing code is broken.")
end

function considerChangingOreEntity(resourceEntity, surface)
	local minDistFromSpawn = settings.global["FunkedOre-min-distance-from-spawn"].value
	if minDistFromSpawn ~= 0 then
		local dist = distance(resourceEntity.position, {x=0, y=0})
		if dist < minDistFromSpawn then return end
	end

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