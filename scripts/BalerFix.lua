BalerFix = {};

function BalerFix:updateOverwritten(_, dt)

    if self.firstTimeRun and self.baler.balesToLoad ~= nil then
        if table.getn(self.baler.balesToLoad) > 0 then
            local v = self.baler.balesToLoad[1];

            if v.targetBaleTime == nil then
                self:createBale(v.fillType, v.fillLevel)
                self:setBaleTime(table.getn(self.baler.bales), 0, true);
                v.targetBaleTime = v.baleTime;
                v.baleTime = 0;
            else
                v.baleTime = math.min(v.baleTime + dt / 1000, v.targetBaleTime);
                self:setBaleTime(table.getn(self.baler.bales), v.baleTime, true);

                if v.baleTime == v.targetBaleTime then

                    local index = table.getn(self.baler.balesToLoad);
                    if index == 1 then
                        self.baler.balesToLoad = nil;
                    else
                        table.remove(self.baler.balesToLoad, 1);
                    end;
                end;
            end;
        end;
    end

    if self.firstTimeRun and self.baler.baleToCreate ~= nil then
        self:createBale(self:getUnitFillType(self.baler.fillUnitIndex), self:getUnitCapacity(self.baler.fillUnitIndex))
        g_server:broadcastEvent(BalerCreateBaleEvent:new(self, self:getUnitFillType(self.baler.fillUnitIndex), 0), nil, nil, self)

        self.baler.baleToCreate = nil;
    end;

    if self:getIsActiveForInput() then
        if InputBinding.hasEvent(InputBinding.IMPLEMENT_EXTRA3) then
            if self:isUnloadingAllowed() then
                if self.baler.baleUnloadAnimationName ~= nil or self.baler.allowsBaleUnloading then
                    if self.baler.unloadingState == Baler.UNLOADING_CLOSED then
                        if table.getn(self.baler.bales) > 0 then
                            self:setIsUnloadingBale(true)

                        elseif self:getUnitFillLevel(self.baler.fillUnitIndex) > 0 then
                        	-- If bale is "large enough"

							if self.baler.baleAnimCurve ~= nil then
                                self:createBale(self:getUnitFillType(self.baler.fillUnitIndex), self:getUnitFillLevel(self.baler.fillUnitIndex))

                                local restDeltaFillLevel = self.balerFix.deltaLevel - (self:getUnitFillLevel(self.baler.fillUnitIndex)-self.balerFix.oldFillLevel)
                                self:setUnitFillLevel(self.baler.fillUnitIndex, 0, FillUtil.FILLTYPE_UNKNOWN, true)

                                local numBales = table.getn(self.baler.bales)
                                local bale = self.baler.bales[numBales]

                                self:moveBale(numBales, self:getTimeFromLevel(restDeltaFillLevel), true)
                                -- note: self.baler.bales[numBales] can not be accessed anymore since the bale might be dropped already
                                g_server:broadcastEvent(BalerCreateBaleEvent:new(self, self.balerFix.usedFillType, bale.time), nil, nil, self)
                            elseif self.baler.baleUnloadAnimationName ~= nil then
                                self:createBale(self:getUnitFillType(self.baler.fillUnitIndex), self:getUnitFillLevel(self.baler.fillUnitIndex))
                                g_server:broadcastEvent(BalerCreateBaleEvent:new(self, self.balerFix.usedFillType, 0), nil, nil, self)
                            end
                            self:setIsUnloadingBale(true)
                			SoundUtil.stopSample(self.baler.sampleBalerAlarm)
                        end
                    elseif self.baler.unloadingState == Baler.UNLOADING_OPEN then
                        if self.baler.baleUnloadAnimationName ~= nil then
                            self:setIsUnloadingBale(false)
                        end
                    end
                end
            end
        end

        if self.baler.baleTypes[self.baler.currentBaleTypeId].isRoundBale ~= nil and self.baler.baleTypes[self.baler.currentBaleTypeId].isRoundBale == true then

	        if InputBinding.hasEvent(InputBinding.T93_CHANGE_MARGIN) then
	        	self.balerFix.baleAlarmFactorIndex = self.balerFix.baleAlarmFactorIndex + 1;
	        	if self.balerFix.baleAlarmFactorTable[self.balerFix.baleAlarmFactorIndex] == nil then
	        		self.balerFix.baleAlarmFactorIndex = 1;
	        	end
	        end

		    g_currentMission:addHelpButtonText(string.format(g_i18n:getText("T93_F1_CHANGE_MARGIN"), (self.balerFix.baleAlarmFactorTable[self.balerFix.baleAlarmFactorIndex]*100)), InputBinding.T93_CHANGE_MARGIN);
		end
    end

    if self.isClient then
        Utils.updateRotationNodes(self, self.baler.turnedOnRotationNodes, dt, self:getIsActive() and self:getIsTurnedOn() )
        Utils.updateScrollers(self.baler.uvScrollParts, dt, self:getIsActive() and self:getIsTurnedOn())
    end
end

function BalerFix:updateTickOverwritten(_, dt)
    self.baler.isSpeedLimitActive = false

    if self.isServer then
        self.baler.lastAreaBiggerZero = false
    end

    if self:getIsActive() then
        if self:getIsTurnedOn() then
            if self:allowPickingUp() then
                if g_currentMission:getCanAddLimitedObject(FSBaseMission.LIMITED_OBJECT_TYPE_BALE) then
                    self.baler.isSpeedLimitActive = true
                    if self.isServer then
                        local workAreas, _, _ = self:getTypedNetworkAreas(WorkArea.AREATYPE_BALER, false)
                        local totalLiters = 0
                        local usedFillType = FillUtil.FILLTYPE_UNKNOWN
                        if table.getn(workAreas) > 0 then
                            totalLiters, usedFillType = self:processBalerAreas(workAreas, self.baler.pickupFillTypes)
	                    	self.balerFix.usedFillType = usedFillType;
                        end

                        if totalLiters > 0 then
                            self.baler.lastAreaBiggerZero = true
                            if self.baler.lastAreaBiggerZero ~= self.baler.lastAreaBiggerZeroSent then
                                self:raiseDirtyFlags(self.baler.dirtyFlag)
                                self.baler.lastAreaBiggerZeroSent = self.baler.lastAreaBiggerZero
                            end

                            local deltaLevel = totalLiters * self.baler.fillScale
                            self.balerFix.deltaLevel = deltaLevel;

                            if self.baler.baleUnloadAnimationName == nil then
                                -- move all bales
                                local deltaTime = self:getTimeFromLevel(deltaLevel)
                                self:moveBales(deltaTime)
                            end

                            local oldFillLevel = self:getUnitFillLevel(self.baler.fillUnitIndex)
                        	self.balerFix.oldFillLevel = oldFillLevel;

                            self:setUnitFillLevel(self.baler.fillUnitIndex, oldFillLevel+deltaLevel, usedFillType, true)
                            if self:getUnitFillLevel(self.baler.fillUnitIndex) >= self:getUnitCapacity(self.baler.fillUnitIndex) then
                                if self.baler.baleTypes ~= nil then
                                    -- create bale
                                    if self.baler.baleAnimCurve ~= nil then
                                        local restDeltaFillLevel = deltaLevel - (self:getUnitFillLevel(self.baler.fillUnitIndex)-oldFillLevel)
                                        self:setUnitFillLevel(self.baler.fillUnitIndex, restDeltaFillLevel, usedFillType, true)

                                        self:createBale(usedFillType, self:getUnitCapacity(self.baler.fillUnitIndex))

                                        local numBales = table.getn(self.baler.bales)
                                        local bale = self.baler.bales[numBales]

                                        self:moveBale(numBales, self:getTimeFromLevel(restDeltaFillLevel), true)
                                        -- note: self.baler.bales[numBales] can not be accessed anymore since the bale might be dropped already
                                        g_server:broadcastEvent(BalerCreateBaleEvent:new(self, usedFillType, bale.time), nil, nil, self)
                                    elseif self.baler.baleUnloadAnimationName ~= nil then
                                        self:createBale(usedFillType, self:getUnitCapacity(self.baler.fillUnitIndex))
                                        g_server:broadcastEvent(BalerCreateBaleEvent:new(self, usedFillType, 0), nil, nil, self)
                                    end
                                end
                            end
                        end
                    end
                else
                    g_currentMission:showBlinkingWarning(g_i18n:getText("warning_tooManyBales"), 500)
                end
            end


            if self.baler.lastAreaBiggerZero and self.fillUnits[self.baler.fillUnitIndex].lastValidFillType ~= FillUtil.FILLTYPE_UNKNOWN then
                self.baler.lastAreaBiggerZeroTime = 500
            else
                if self.baler.lastAreaBiggerZeroTime > 0 then
                    self.baler.lastAreaBiggerZeroTime = self.baler.lastAreaBiggerZeroTime - dt
                end
            end

            if self.isClient then
                if self.baler.fillEffects ~= nil then
                    if self.baler.lastAreaBiggerZeroTime > 0 then
                        EffectManager:setFillType(self.baler.fillEffects, self.fillUnits[self.baler.fillUnitIndex].lastValidFillType)
                        EffectManager:startEffects(self.baler.fillEffects)
                    else
                        EffectManager:stopEffects(self.baler.fillEffects)
                    end
                end

                local currentFillParticleSystem = self.baler.fillParticleSystems[self.fillUnits[self.baler.fillUnitIndex].lastValidFillType]
                if currentFillParticleSystem ~= self.baler.currentFillParticleSystem then
                    if self.baler.currentFillParticleSystem ~= nil then
                        for _, ps in pairs(self.baler.currentFillParticleSystem) do
                            ParticleUtil.setEmittingState(ps, false)
                        end
                        self.baler.currentFillParticleSystem = nil
                    end
                    self.baler.currentFillParticleSystem = currentFillParticleSystem
                end

                if self.baler.currentFillParticleSystem ~= nil then
                    for _, ps in pairs(self.baler.currentFillParticleSystem) do
                        ParticleUtil.setEmittingState(ps, self.baler.lastAreaBiggerZeroTime > 0)
                    end
                end

                if self:getIsActiveForSound() then
                    if self.baler.knotCleaningTime <= g_currentMission.time then
                        SoundUtil.playSample(self.baler.sampleBalerKnotCleaning, 1, 0, nil)
                        self.baler.knotCleaningTime = g_currentMission.time + 120000
                    end
                    SoundUtil.playSample(self.baler.sampleBaler, 0, 0, nil)
                end
            end
        else
            if self.baler.isBaleUnloading and self.isServer then
                local deltaTime = dt / self.baler.baleUnloadingTime
                self:moveBales(deltaTime)
            end
        end

        if self.isClient then
            if not self:getIsTurnedOn() then
                SoundUtil.stopSample(self.baler.sampleBalerKnotCleaning)
                SoundUtil.stopSample(self.baler.sampleBaler)
            end

            if self:getIsTurnedOn() and self:getUnitFillLevel(self.baler.fillUnitIndex) > (self:getUnitCapacity(self.baler.fillUnitIndex) * self.balerFix.baleAlarmFactorTable[self.balerFix.baleAlarmFactorIndex]) 
			  and self:getUnitFillLevel(self.baler.fillUnitIndex) < self:getUnitCapacity(self.baler.fillUnitIndex) 
			  and self.baler.unloadingState ~= Baler.UNLOADING_OPENING then

                -- start alarm sound
                if self:getIsActiveForSound() then
                    SoundUtil.playSample(self.baler.sampleBalerAlarm, 0, 0, nil)
                end
            else
                SoundUtil.stopSample(self.baler.sampleBalerAlarm)
            end

            --delete dummy bale on client after physical bale is displayed
            if self.baler.unloadingState == Baler.UNLOADING_OPEN then
                if getNumOfChildren(self.baler.baleAnimRoot) > 0 then
                    delete(getChildAt(self.baler.baleAnimRoot, 0));
                end;
            end;
        end;

        if self.baler.unloadingState == Baler.UNLOADING_OPENING then
            local isPlaying = self:getIsAnimationPlaying(self.baler.baleUnloadAnimationName)
            local animTime = self:getRealAnimationTime(self.baler.baleUnloadAnimationName)
            if not isPlaying or animTime >= self.baler.baleDropAnimTime then
                if table.getn(self.baler.bales) > 0 then
                    self:dropBale(1)
                    if self.isServer then
                        self:setUnitFillLevel(self.baler.fillUnitIndex, 0, self:getUnitFillType(self.baler.fillUnitIndex), true)
                    end
                end
                if not isPlaying then
                    self.baler.unloadingState = Baler.UNLOADING_OPEN

                    if self.isClient then
                        SoundUtil.stopSample(self.baler.sampleBalerEject)
                        SoundUtil.stopSample(self.baler.sampleBalerDoor)
                    end
                end
            end
        elseif self.baler.unloadingState == Baler.UNLOADING_CLOSING then
            if not self:getIsAnimationPlaying(self.baler.baleCloseAnimationName) then
                self.baler.unloadingState = Baler.UNLOADING_CLOSED
                if self.isClient then
                    SoundUtil.stopSample(self.baler.sampleBalerDoor)
                end
            end
        end
    end
end

function BalerFix:drawOverwritten()
    if self.isClient then
        if self:getIsActiveForInput(true) then
            if self:isUnloadingAllowed() then
                if self.baler.baleUnloadAnimationName ~= nil or self.baler.allowsBaleUnloading then
                    if self.baler.unloadingState == Baler.UNLOADING_CLOSED then
                        if table.getn(self.baler.bales) > 0 or self:getUnitFillLevel(self.baler.fillUnitIndex) > 0 then
                            g_currentMission:addHelpButtonText(g_i18n:getText("action_unloadBaler"), InputBinding.IMPLEMENT_EXTRA3, nil, GS_PRIO_HIGH)
                        end
                    elseif self.baler.unloadingState == Baler.UNLOADING_OPEN then
                        if self.baler.baleUnloadAnimationName ~= nil then
                            g_currentMission:addHelpButtonText(g_i18n:getText("action_closeBack"), InputBinding.IMPLEMENT_EXTRA3, nil, GS_PRIO_HIGH)
                        end
                    end
                end
            end
        end
    end
end

function BalerFix:loadAppend()
	self.balerFix = {};
	self.balerFix.deltaLevel = 0;
	self.balerFix.oldFillLevel = 0;
	self.balerFix.usedFillType = 0;

	self.balerFix.baleAlarmFactorTable = {0.5, 0.75, 0.85, 0.90, 0.95, 1}
	self.balerFix.baleAlarmFactorIndex = 3;
end

function BalerFix:loadMap(name)
	Baler.updateTick = Utils.overwrittenFunction(Baler.updateTick, BalerFix.updateTickOverwritten);
	Baler.update = Utils.overwrittenFunction(Baler.update, BalerFix.updateOverwritten);
	Baler.draw = Utils.overwrittenFunction(Baler.draw, BalerFix.drawOverwritten);
	Baler.load = Utils.appendedFunction(Baler.load, BalerFix.loadAppend);
end;

function BalerFix:deleteMap()end;
function BalerFix:keyEvent(unicode, sym, modifier, isDown)end;
function BalerFix:mouseEvent(posX, posY, isDown, isUp, button)end;
function BalerFix:update(dt)end;
function BalerFix:draw()end;

addModEventListener(BalerFix);