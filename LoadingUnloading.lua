
--basic trigger functions for Loading at grain silos/ filling implements and Unloading to triggers and ...

function courseplay:checkAIDriver(vehicle) 
	if vehicle and vehicle.cp and vehicle.cp.driver and vehicle:getIsCourseplayDriving() then 
		return true
	end
	return false
end

-- Custom version of trigger:onActivateObject to allow activating for a non-controlled vehicle
function courseplay:activateTriggerForVehicle(trigger, vehicle)
	--Cache giant values to restore later
	local defaultGetFarmIdFunction = g_currentMission.getFarmId;
	local oldControlledVehicle = g_currentMission.controlledVehicle;

	--Override farm id to match the calling vehicle (fixes issue when obtaining fill levels)
	local overriddenFarmIdFunc = function()
		local ownerFarmId = vehicle:getOwnerFarmId()
		courseplay.debugVehicle(19, vehicle, 'Overriding farm id during trigger activation to %d', ownerFarmId);
		return ownerFarmId;
	end
	g_currentMission.getFarmId = overriddenFarmIdFunc;

	--Override controlled vehicle if I'm not in it
	if g_currentMission.controlledVehicle ~= vehicle then
		g_currentMission.controlledVehicle = vehicle;
	end

	--Call giant method with new params set
	trigger:onActivateObject(vehicle);

	--Restore previous values
	g_currentMission.getFarmId = defaultGetFarmIdFunction;
	g_currentMission.controlledVehicle = oldControlledVehicle;
end

--LoadTrigger scan if trigger is activatable
function courseplay:isTriggerAvailable(vehicle)
    for key, object in pairs(g_currentMission.activatableObjects) do
		if object:getIsActivatable(vehicle) then
            g_currentMission.activatableObjects[key] = nil
			courseplay:activateTriggerForVehicle(object, vehicle)
		    return true
        end
    end
    return false
end

--LoadTrigger override of onActivateObject to disable fruitSelectMenu and also check if we are at a fuel trigger
function courseplay:onActivateObject(superFunc,vehicle)
	if courseplay:checkAIDriver(vehicle) then 
		local dieselIndex = vehicle:getConsumerFillUnitIndex(FillType.DIESEL)
		courseplay.debugVehicle(19, vehicle, 'onActivateObject Load Trigger')
		if not self.isLoading then
			local fillLevels, capacity = self.source:getAllFillLevels(g_currentMission:getFarmId())
			local fillableObject = self.validFillableObject
			local fillUnitIndex = self.validFillableFillUnitIndex
			local validFillTypIndexes = {}
			for fillTypeIndex, fillLevel in pairs(fillLevels) do
				if self.fillTypes == nil or self.fillTypes[fillTypeIndex] then
					if fillableObject:getFillUnitAllowsFillType(fillUnitIndex, fillTypeIndex) then
						if dieselIndex and fillTypeIndex == dieselIndex and vehicle.spec_motorized then 
							motorSpec = vehicle.spec_motorized
							courseplay.debugVehicle(19, vehicle, 'Fuell Trigger found')
							if vehicle.cp.settings.allwaysSearchFuel:is(false) then
								if not vehicle:getFillUnitFillLevelPercentage(motorSpec.consumersByFillTypeName.def.fillUnitIndex)*100 < 20 then 
									courseplay.debugVehicle(19, vehicle, 'still enough fuel in Vehicle')
									return superFunc(self,trigger, fillTypeIndex, fillUnitIndex)
								end
							end
							self:onFillTypeSelection(fillTypeIndex)
							return
						else
							if fillLevel > 0 then 
								table.insert(validFillTypIndexes,fillTypeIndex)						
							end
						end
					end
				end
			end
			local totalData = vehicle.cp.settings.siloSelectedFillType:getData()
			if #validFillTypIndexes >0 and totalData then 
				courseplay.debugVehicle(19, vehicle, 'validFillTypes found')
				for _,data in ipairs(totalData) do 
					courseplay.debugVehicle(19, vehicle, 'selected filltypes: '..g_fillTypeManager:getFillTypeByIndex(data.value).title)
					for _,fillType in pairs(validFillTypIndexes) do						
						if fillType == data.value then 	
							if vehicle.cp.driver:is_a(CombineUnloadAIDriver) then 
								courseplay.debugVehicle(19, vehicle, 'wrong AIDriver')
								return
							end
							courseplay.debugVehicle(19, vehicle, 'select Filltype Load Trigger')
							if data.runCounter > 0 then
								courseplay.debugVehicle(19, vehicle, 'select Filltype Load Trigger')
								self:onFillTypeSelection(data.value)
								data.runCounter = data.runCounter-1
								return
							else
								courseplay.debugVehicle(19, vehicle, 'passedRunCounter => no more loading!')
							end
						end
					end
				end
			end
			
			
			--FillableFieldworkDriver
	--		if siloSelectedFillType == FillType.UNKNOWN then 
	--			if #validFillTypIndexes >0 then 
	--				fillableObject:addFillUnitTrigger(nil,validFillTypIndexes[1],fillUnitIndex)
	--				self:onFillTypeSelection(validFillTypIndexes[1])
	--			end
	--		end
			CpManager:setGlobalInfoText(vehicle, 'FARM_SILO_NO_FILLTYPE')
			if not fillableObject:getFillUnitFillType() then 
				vehicle.cp.driver:setLoadingState()
				courseplay.debugVehicle(19, vehicle, 'wrong FillType and empty => wait')
			else
				courseplay.debugVehicle(19, vehicle, 'wrong FillType ??')
			end
		end
	else 
		return superFunc(self)
	end
end
LoadTrigger.onActivateObject = Utils.overwrittenFunction(LoadTrigger.onActivateObject,courseplay.onActivateObject)

--loadTriggerCallback as direct entry point for CP to open/close Covers 
--might have to use "onAddedFillUnitTrigger"
--TODO: needs some tweaking
function courseplay:loadTriggerCallback(superFunc,triggerId, otherId, onEnter, onLeave, onStay, otherShapeId)
	local fillableObject = g_currentMission:getNodeObject(otherId)
	local rootVehicle
	if fillableObject then 
		rootVehicle = fillableObject:getRootVehicle()
	end
	if courseplay:checkAIDriver(rootVehicle)  then 
		if onEnter then 
			courseplay.debugVehicle(19, vehicle, 'onEnter LoadTrigger ')
			courseplay:openCloseCover(fillableObject, true)
		end
		if onLeave then 
			courseplay.debugVehicle(19, vehicle, 'onLeave LoadTrigger ')
			courseplay:openCloseCover(fillableObject, false)
		end
	end
	return superFunc(self,triggerId, otherId, onEnter, onLeave, onStay, otherShapeId)
end
LoadTrigger.loadTriggerCallback = Utils.overwrittenFunction(LoadTrigger.loadTriggerCallback,courseplay.loadTriggerCallback)

--simple trigger scan for unloading Triggers
--is this useable for shovels -> bunker silo ??
--or shovel in general ??
--TODO: needs more tweaking
function courseplay:isUnloadingTriggerAvailable(object)    
	local spec = object.spec_dischargeable
	if spec then 
		if spec:getCanToggleDischargeToObject() then 
			local currentDischargeNode = spec.currentDischargeNode
			if currentDischargeNode and spec.currentDischargeState == Dischargeable.DISCHARGE_STATE_OFF then
				if spec:getCanDischargeToObject(currentDischargeNode) then
					spec:setDischargeState(Dischargeable.DISCHARGE_STATE_OBJECT)
				elseif currentDischargeNode.dischargeHit then
				
				else 
				
				end
			end
		end
	end
	for _,impl in pairs(object:getAttachedImplements()) do
		courseplay:isUnloadingTriggerAvailable(impl.object)
	end
end

--override of setDischargeState() to start/stop driver while unloading at triggers, 
--might be tricky with unloading at BunkerSilo while driving ??
function courseplay:setDischargeState(superFunc,state, noEventSend)
    local rootVehicle = self:getRootVehicle()
	--might break harvesters/combines ??
	if rootVehicle and rootVehicle.spec_combine then 
		return superFunc(self,state,noEventSend)
	end
	if courseplay:checkAIDriver(rootVehicle) then 
		courseplay.debugVehicle(19, vehicle, 'setDischargeState')
		if state == Dischargeable.DISCHARGE_STATE_OFF  then
			rootVehicle.cp.driver:resetUnloadingState()			
			courseplay.debugVehicle(19, vehicle, 'stop Unloading')
		elseif state == Dischargeable.DISCHARGE_STATE_OBJECT then
			rootVehicle.cp.driver:setUnloadingState()
			courseplay.debugVehicle(19, vehicle, 'start Unloading')
		end
	end
	return superFunc(self,state,noEventSend)
end
Dischargeable.setDischargeState = Utils.overwrittenFunction(Dischargeable.setDischargeState,courseplay.setDischargeState)

--used for for FillTriggers, like pallets... , for sowers/sprayers ...
function courseplay:addFillUnitTrigger(superFunc,trigger, fillTypeIndex, fillUnitIndex)
	local rootVehicle = self:getRootVehicle()
	if courseplay:checkAIDriver(rootVehicle) then 
		--Try this one so TransportDriver is not using trigger unless it's filling up fuel.
		if not fillTypeIndex == FillType.DIESEL and rootVehicle.cp.driver:is_a(AIDriver) then 
			return superFunc(self,trigger, fillTypeIndex, fillUnitIndex)
		end
		if trigger then
			local spec = self.spec_fillUnit
			local possible = false
			if #spec.fillTrigger.triggers == 0 then
				courseplay.debugVehicle(19, vehicle, 'FillUnit: addFillUnitTrigger')
				spec.fillTrigger.activatable:setFillType(fillTypeIndex)
				possible = true
			end
			ListUtil.addElementToList(spec.fillTrigger.triggers, trigger)
			SpecializationUtil.raiseEvent(self, "onAddedFillUnitTrigger", fillTypeIndex, fillUnitIndex, #spec.fillTrigger.triggers)
			if possible then
				spec:setFillUnitIsFilling(true)
				courseplay.debugVehicle(19, vehicle, 'FillUnit: setFillUnitIsFilling')
			end
			return
		else
			SpecializationUtil.raiseEvent(self, "onAddedFillUnitTrigger", fillTypeIndex, fillUnitIndex)
			return
		end
	end
	return superFunc(self,trigger, fillTypeIndex, fillUnitIndex)
end
FillUnit.addFillUnitTrigger = Utils.overwrittenFunction(FillUnit.addFillUnitTrigger,courseplay.addFillUnitTrigger)

--force Driver to start/stop while loading on FillTriggers
function courseplay:setFillUnitIsFilling(superFunc,isFilling, noEventSend)
	local rootVehicle = self:getRootVehicle()
	if courseplay:checkAIDriver(rootVehicle) then 
		if isFilling == true then 
			courseplay.debugVehicle(19, vehicle, 'FillUnit: setFillUnitIsFilling is filling for')
			rootVehicle.cp.driver:setLoadingState()
		else 
			courseplay.debugVehicle(19, vehicle, 'FillUnit: setFillUnitIsFilling is full/stopped ')
			rootVehicle.cp.driver:resetLoadingState(self)
		end	
	end
	return superFunc(self,isFilling, noEventSend)
end
FillUnit.setFillUnitIsFilling = Utils.overwrittenFunction(FillUnit.setFillUnitIsFilling,courseplay.setFillUnitIsFilling)

--force Driver to start/stop while loading on LoadTriggers
function courseplay:setIsLoading(superFunc,isLoading, targetObject, fillUnitIndex, fillType, noEventSend)
    courseplay.debugVehicle(19, vehicle, 'LoadTrigger: setIsLoading')
	local rootVehicle = self.validFillableObject:getRootVehicle()
	if courseplay:checkAIDriver(rootVehicle) then
		if isLoading then 
			courseplay.debugVehicle(19, vehicle, 'LoadTrigger: setIsLoading is Loading ')
			rootVehicle.cp.driver:setLoadingState()
			rootVehicle.cp.driver:setTrigger(self)
		else 
			courseplay.debugVehicle(19, vehicle, 'LoadTrigger: setIsLoading is full/stopped')
			rootVehicle.cp.driver:resetLoadingState(self.validFillableObject)
			rootVehicle.cp.driver:resetTrigger(validFillableObject)
		end
	end
	return superFunc(self,isLoading, targetObject, fillUnitIndex, fillType, noEventSend)
end
LoadTrigger.setIsLoading = Utils.overwrittenFunction(LoadTrigger.setIsLoading,courseplay.setIsLoading)

-- LoadTrigger doesn't allow filling non controlled tools
function courseplay:getIsActivatable(superFunc,objectToFill)
	--when the trigger is filling, it uses this function without objectToFill
	if objectToFill ~= nil then
		local vehicle = objectToFill:getRootVehicle()
		if objectToFill:getIsCourseplayDriving() or (vehicle~= nil and vehicle:getIsCourseplayDriving()) then
			--if i'm in the vehicle, all is good and I can use the normal function, if not, i have to cheat:
			if g_currentMission.controlledVehicle ~= vehicle then
				local oldControlledVehicle = g_currentMission.controlledVehicle;
				g_currentMission.controlledVehicle = vehicle or objectToFill;
				local result = superFunc(self,objectToFill);
				g_currentMission.controlledVehicle = oldControlledVehicle;
				return result;
			end
		end
	end
	return superFunc(self,objectToFill);
end
LoadTrigger.getIsActivatable = Utils.overwrittenFunction(LoadTrigger.getIsActivatable,courseplay.getIsActivatable)

--close cover after tipping if not closed already
function courseplay:endTipping(superFunc,noEventSend)
	local rootVehicle = self:getRootVehicle()
	if courseplay:checkAIDriver(rootVehicle) then
		if rootVehicle.cp.settings.automaticCoverHandling:is(true) and self.spec_cover then
			self:setCoverState(0, true)
		end
	end
	return superFunc(self,noEventSend)
end
Trailer.endTipping = Utils.overwrittenFunction(Trailer.endTipping,courseplay.endTipping)

--callback for pips if pipe is over implement oven cover and for shovels i am guessing
function courseplay:unloadingTriggerCallback(superFunc,triggerId, otherId, onEnter, onLeave, onStay, otherShapeId)
	local fillableObject = g_currentMission:getNodeObject(otherId)
	local rootVehicle
	if fillableObject then 
		rootVehicle = fillableObject:getRootVehicle()
	end
	if courseplay:checkAIDriver(rootVehicle) then 
		if onEnter then 
			if fillableObject.spec_cover and fillableObject.getFillUnitIndexFromNode ~= nil then 
				local fillUnitIndex = fillableObject:getFillUnitIndexFromNode(otherId)
                if fillUnitIndex ~= nil then
					local dischargeNode = self:getDischargeNodeByIndex(self:getPipeDischargeNodeIndex())
					local fillType = nil
					if dischargeNode ~= nil then
                        fillType = self:getFillUnitFillType(dischargeNode.fillUnitIndex)
					end
					if fillType then 
						courseplay.debugVehicle(19, vehicle, 'open Cover for Pipe/Unloading Trigger')
						fillableObject:addFillUnitTrigger(nil,fillType,fillUnitIndex)
					end
				end
			end
			
			courseplay.debugVehicle(19, vehicle, 'onEnter UnloadingTrigger ')
		--	courseplay:openCloseCover(fillableObject, true)
		end
		if onLeave then 
			courseplay.debugVehicle(19, vehicle, 'onLeave UnloadingTrigger ')
		--	courseplay:openCloseCover(fillableObject, false)
		end
	end

	return superFunc(self,triggerId, otherId, onEnter, onLeave, onStay, otherShapeId)
end
Pipe.unloadingTriggerCallback = Utils.overwrittenFunction(Pipe.unloadingTriggerCallback,courseplay.unloadingTriggerCallback)


--Bunker Silo Callback ,have to get the local hitbox of where to unload maybe in the bunkersilo:load ??
function courseplay:interactionTriggerCallback(superFunc,triggerId, otherId, onEnter, onLeave, onStay, otherShapeId)
	if onEnter then
		courseplay.debugVehicle(19, vehicle, 'BunkerSilo onEnter')
	end
	if onLeave then 
		courseplay.debugVehicle(19, vehicle, 'BunkerSilo onLeave')
	end
	return superFunc(self,triggerId, otherId, onEnter, onLeave, onStay, otherShapeId)
end
BunkerSilo.interactionTriggerCallback = Utils.overwrittenFunction(BunkerSilo.interactionTriggerCallback,courseplay.interactionTriggerCallback)

