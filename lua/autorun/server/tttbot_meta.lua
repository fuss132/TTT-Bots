--// Metatable functions //

local entmeta = FindMetaTable("Entity")

--// Returns true if the given entity is, in fact, a door
function entmeta:isDoor()
	if not IsValid( self ) or self:IsPlayer() then return false end
	
	local class = self:GetClass()
	if class == "prop_door_rotating" or class == "func_door" or class == "func_door_rotating" then
		return true
	end
	return false
end

local plymeta = FindMetaTable( "Player" )

function plymeta:generateNav( callback )

	local navmesh = nav.Create( 64 )
	self.tttBot_nav = navmesh -- Global variable to access the navmesh

	navmesh:SetDiagonal( true )
	navmesh:SetMask( MASK_PLAYERSOLID )
	
	local HitWorld = true
	local Pos = Vector( 150.98213195801, -317.26312255859, 64.03125 )
	local Normal = Vector( 0, 0, 0 )
	local NormalUp = Vector(0, 0, 1)

	if(HitWorld) then
		ErrorNoHalt("Creating navmesh\n")
		
		if IsValid( self ) then
			-- Remove this line if you don't want a max distance
			navmesh:SetupMaxDistance(self:GetPos(), 1024) -- All nodes must stay within 256 vector distance from the players position
		end
		
		navmesh:ClearGroundSeeds()
		navmesh:ClearAirSeeds()
		
		-- Once 1 seed runs out, it will go onto the next seed
		navmesh:AddGroundSeed(Pos, Normal)
		
		-- The module will account for node overlapping
		navmesh:AddGroundSeed(Pos, NormalUp)
		navmesh:AddGroundSeed(Pos, NormalUp)
		
		local StartTime = os.time()
		
		navmesh:Generate( function(navmesh)
			ErrorNoHalt("Generated "..navmesh:GetNodeTotal().." nodes in "..string.ToMinutesSeconds(os.time() - StartTime).."\n")
			
			if callback then
				callback()
			end
		end, 
		function( navmesh, GeneratedNodes )
			ErrorNoHalt("Generated "..GeneratedNodes.." nodes so far\n")
		end)
	end
end

--// Generates a path from the bot's position to the given vector
function plymeta:generatePathTo( pos )
	local navmesh = self.tttBot_nav
	
	print("generatePathTo", pos)
	
	-- This bot doesn't have a nav, generate one so it has purpose in life
	if not navmesh then
		print(self:Nick().." does not have a valid nav mesh! Generating one...")
		self:setPathing( false )
		self:generateNav( function()
			self:generatePathTo( pos )
		end)
		return
	end
	
	-- Nav is still generating, don't do anything stupid
	if not navmesh:IsGenerated() then
		print("Nav is still generating")
		self:setPathing( false )
		return
	end
	
	self.failedPathTries = self.failedPathTries or 0
	
	-- Failed to generate a path too many times
	if self.failedPathTries > 5 then
		if pos == self.failedPathPos then
			-- Generate a new nav because that sometimes fixes it
			print("Failed to generate path too many times")
			self:setPathing( false )
			self:generateNav()
			return
		else
			self.failedPathTries = 0
		end
	end
		
	-- Hull dimensions
	local mins = Vector(-16, -16, 20)
	local maxs = Vector(16, 16, 72)

	local startNode = navmesh:GetClosestNode( self:GetPos() )
	--local endNode = navmesh:GetClosestNode( findExho():GetPos() )
	local endNode = navmesh:GetClosestNode( pos )
	
	-- For some reason this module likes to return invalid nodes as false instead of nil
	if type(startNode) != "boolean" and type(endNode) != "boolean" then
		navmesh:SetStart( startNode )
		navmesh:SetEnd( endNode )
	end
	
	ErrorNoHalt("ComputePath\n")
	
	local startTime = os.time()
	
	navmesh:FindPathHull(mins, maxs, function(navmesh, bFoundPath, path)
		if bFoundPath then
			ErrorNoHalt("Found Path in "..string.ToMinutesSeconds(os.time() - startTime).." Path Size: "..table.Count(path).."\n")
			
			self.currentPath = path
			self.currentPathKey = 2 -- Ignore the nodes that we are standing on
			self.currentPathStart = navmesh:GetStart()
			self.currentPathEnd = navmesh:GetEnd()
			
			self.generatingPath = false
			
			self:setPathing( true )
			
			--showPath( path )
		else
			ErrorNoHalt("Failed to Find Path\n")
			self.generatingPath = false
			
			self:setPathing( false )
			
			if pos == self.failedPathPos then
				self.failedPathTries = self.failedPathTries + 1
			else
				self.failedPathPos = pos
				self.failedPathTries = 0
			end
		end
	end)
end

--// Sets if the bot is following a path or not
function plymeta:setPathing( bFollow )
	self.tttBot_followingPath = bFollow
end

--// Returns if the bot is following a path or not
function plymeta:getPathing()
	return self.tttBot_followingPath
end

--// Called every tick to make the bot follow its previously generated path
function plymeta:followPath()
	local cmd = self.cmd
	
	-- Path exists
	if self.currentPath and self:getPathing() then
		local path = self.currentPath
		local pathKey = self.currentPathKey
		local pathStart = self.currentPathStart
		local pathEnd = self.currentPathEnd
		
		local nextNode = path[pathKey+1]
		
		-- The next node isn't valid
		if not nextNode then 
			print("Next node is invalid")
			self.currentPathKey = pathKey + 1
			pathKey = pathKey + 1
			nextNode = path[pathKey+1]
			
			-- The next node doesn't exist, we've reached the end of the path
			if not nextNode then
				print("There are no more nodes", #path, pathKey)
				self.currentPath = nil
				self.currentPathKey = nil
				self.currentPathStart = nil
				self.currentPathEnd = nil
				
				self:setPathing( false )
			end
			return
		end
		
		local nextVector = nextNode:GetPosition()
		
		-- Walk towards the next position in the path
		cmd:SetForwardMove( tttBot.speed )
		self:lookAtPos( nextVector )
		
		print(self:GetPos():Distance( nextVector ))
		
		-- We are close enough to the vector to be done
		if self:GetPos():Distance( nextVector ) < 50 then
			print("Increment key")
			self.currentPathKey = pathKey + 1
		end
	end
end

--// Makes sure the bots don't get selected for Detective 
-- TODO This should probably hooked onto Initialize so it overrides TTT's function
hook.Add("Initialize", "tttBots_avoidDetective", function()
	function plymeta:GetAvoidDetective()
		if self.IsBot and self:IsBot() then print("Bot's shouldn't be detective") return true end
		
		return self:GetInfoNum("ttt_avoid_detective", 0) > 0
	end
end)

--// Sets the target for the bot
function plymeta:setTarget( target )
	self.tttBot_target = target
end

--// Returns the target for the bot
function plymeta:getTarget()
	return self.tttBot_target
end

--// Sets the bot's new position to walk to
function plymeta:setNewPos( vector )
	self.tttBot_newPos = vector
end

--// Returns the bot's new position to walk to
function plymeta:getNewPos()
	return self.tttBot_newPos
end

--// Sets the new eye angles for the bot to interpolate to
function plymeta:setNewAngles( ang )
	self.tttBot_oldAng = self:EyeAngles()
	self.tttBot_newAng = ang
end

--// Returns the new eye angles for the bot to interpolate to
function plymeta:getNewAngles()
	return self.tttBot_newAng, self.tttBot_oldAng
end

--// Makes the bot stand still 
function plymeta:idle()
	local cmd = self.cmd
	
	cmd:ClearMovement()
	cmd:ClearButtons()
end

--// Locates a new player to attack thats close
function plymeta:findNewTarget( bLazy )
	local players = player.GetAll()

	local target 
	local closestDist = 100000
	
	if #players > 1 then
		for key, ply in pairs( players ) do
			if IsValid( ply ) and ply:Alive() and ply != self and ply:GetRole() != self:GetRole() then
				local dist = self:GetPos():Distance( ply:GetPos() )
				
				-- Choose the target if they are closer than the previous one or if bLazy == true then we just pick a random player
				if dist < closestDist and (bLazy or self:isVectorVisible( ply:GetPos() )) then
					closestDist = dist
					target = ply
				end
			end
		end
	end
	
	-- Can't immediately find a target, go try to find a gun
	if not IsValid( target ) then
		self.tttBot_endGunSearchTime = CurTime() + math.random(5, 15)
	end

	return target
end

--// Lerps the bot's view angles so the bot doesn't snap around
function plymeta:lerpAngles()	
	local cmd = self.cmd

	local eyeAng = self.tttBot_oldAng or self:EyeAngles()
	local newAng = self.tttBot_newAng
	
	if newAng then
		cmd:SetViewAngles( LerpAngle( 0.7, eyeAng, newAng ) )
	end
end

--// Returns if the given vector is in the bot's cone of vision
function plymeta:isVectorVisible( pos )
	-- Math that I don't entirely understand
	local cone = math.cos( 30 )
	local dir = (self:GetPos() - pos):GetNormal()
	
	local dot = self:GetForward():Dot( -dir )
	
	local visible = false
	
	if dot > cone then
		visible = true
	end
	
	return visible, dot
end

--// Hunts down and kills the target
local nextPosTrace = 0
function plymeta:huntTarget()
	local cmd = self.cmd
	
	if self:targetIsValid() then
		local ang = self:EyeAngles()
		local tPos = self:getTarget():GetPos()
		local pos = self:GetPos()
		local dist = pos:Distance( tPos )
		
		-- Get the angles between us and the target
		yaw = math.deg(math.atan2(tPos.y - pos.y, tPos.x - pos.x))
		pitch = math.deg(math.atan2( -(tPos.z - pos.z), dist))
		
		-- Is there a clear line between us and the target?
		-- Is the target in our cone of view?
		local clearLOS = self:clearLOS( self:getTarget() )
		local vectorVisible = true
		
		--print(vectorVisible, clearLOS)
		
		-- The target is within our cone of vision and we can see them
		if vectorVisible and clearLOS then
			--self:setNewAngles( Angle( pitch, yaw, 0 ) )
			
			-- Track their position
			self.targetPos = tPos
			
			-- Is this really necessary?
			if CurTime() > nextPosTrace then
				local tracedata = {}
				tracedata.start = tPos
				tracedata.filter = {self}
				tracedata.endpos = tPos + ang:Forward() * 1000
				local trace = util.TraceLine(tracedata)
				
				self:setNewPos( trace.HitPos )
				
				nextPosTrace = CurTime() + 2
			end
		end
		
		-- If we have a last known position of our target, run towards it
		if self.targetPos then
			if not clearLOS and self.targetPos:Distance( self:GetPos() ) < 25 then
				-- We can't see the target and we reached their last known position
				-- They are gone
				self:setTarget( nil )
			else
				self.tttBot_nextPathGen = self.tttBot_nextPathGen or 0
				
				-- Only generate a new path when we are far enough from our target
				-- Otherwise just fall back to the original method of chasing players
				if self.targetPos:Distance( self:GetPos() ) > 100 and CurTime() > self.tttBot_nextPathGen then
					self:generatePathTo( self.targetPos )
					self.tttBot_nextPathGen = CurTime() + 2
				elseif self.targetPos:Distance( self:GetPos() ) < 100 or not self:getPathing() then
					cmd:SetForwardMove( tttBot.speed )
					self:lookAtPos( self.targetPos )
				end
			end
		else
			-- Otherwise Traitor bots should find a new target and everyone else should wander
			if self:GetRole() == ROLE_TRAITOR then
				self:setTarget( self:findNewTarget() )
			else
				self:wander()
			end
		end
		
		if not IsValid( self:GetActiveWeapon() ) then return end
		
		local activeClass = self:GetActiveWeapon():GetClass()
		
		-- We have weapons
		if self:hasGuns() then
			self:selectGun()
			if clearLOS then
				-- Shoot at them
				self:attackTarget()
				
				-- Fake some revoil
				local ang = Angle(pitch, yaw, 0)
				cmd:SetViewAngles( Angle(ang.p + math.random(5, 10), ang.y + math.random(-5,5), ang.r) )
			else
				cmd:ClearButtons()
			end
		elseif dist < 70 and clearLOS then
			-- Whack the target
			self:selectCrowbar()
			self:attackTarget()
		end
	else
		-- Our target isn't valid
		if self:GetRole() == ROLE_TRAITOR then
			print("New target - Hunt")
			-- Traitors should find new targets
			self:setTarget( self:findNewTarget( ) )
		else
			-- Innocents should go wander some more
			print("Delete target - Hunt")
			self:setTarget( nil )
		end
	end
end

local spawns = {
	"info_player_deathmatch", "info_player_combine",
	"info_player_rebel", "info_player_counterterrorist", "info_player_terrorist",
	"info_player_axis", "info_player_allies", "gmod_player_start",
	"info_player_teamspawn", "info_player_start"
}

--// Makes the bot walk between random positions and search for guns every so often
function plymeta:wander()
	local cmd = self.cmd
	
	local newPos = self:getNewPos()
	
	if newPos and self:GetPos():Distance( newPos ) > 50 then
		-- Walk towards the given position
		--self:lookAtPos( newPos )
		--cmd:SetForwardMove( tttBot.speed )
		
		self.tttBot_nextPathGen = self.tttBot_nextPathGen or 0
		
		if CurTime() > self.tttBot_nextPathGen then
			self:generatePathTo( newPos )
			self.tttBot_nextPathGen = CurTime() + 2
		end
		
		if not self:getPathing() then
			cmd:SetForwardMove( tttBot.speed )
			self:lookAtPos( newPos )
		end
		
		--self:generatePathTo( newPos )
	else
		-- Find a new position for the bot to walk to
		self.tttBot_nextWeaponSearch = self.tttBot_nextWeaponSearch or 0
		
		if CurTime() > self.tttBot_nextWeaponSearch and not self:hasGuns() then
			-- Search for a weapon 
			local wep = self:findWeapon()
			
			if not wep then
				self.tttBot_nextWeaponSearch = CurTime() + 5
			end
		else
			local spawnpoints = {}
			
			-- Add spawnpoints
			for _, ent in pairs( ents.GetAll() ) do
				for _, class in pairs( spawns ) do
					if ent:GetClass():lower() == class:lower() then
						table.insert( spawnpoints, ent )
					end
				end
			end
			
			-- Add living players
			for _, v in pairs( player.GetAll() ) do
				if v:Alive() then
					table.insert( spawnpoints, v )
				end
			end
			
			-- Walk to a random entity in this table
			local spawn = table.Random( spawnpoints )
			
			self:setNewPos( spawn:GetPos() + Vector( 0, 0, 30 ) )
		end
	end
end

--// Makes the bot look at a vector
function plymeta:lookAtPos( vector )
	if not IsValid( self ) then return end
	local cmd = self.cmd
	local target = self:getTarget()
	
	local pos = self:GetPos()
	local dist = pos:Distance( vector )
	
	yaw = math.deg(math.atan2(vector.y - pos.y, vector.x - pos.x))
	pitch = math.deg(math.atan2( -(vector.z - pos.z), dist))
	
	self:setNewAngles( Angle( pitch, yaw, 0 ) )
end

--// Returns if the bot's target is valid
function plymeta:targetIsValid()
	local cmd = self.cmd
	local target = self:getTarget()
	
	if not IsValid( target ) then return false end
	if not target:Alive() then return false end
	if target:IsSpec() then return false end
	
	if self:GetRole() == ROLE_TRAITOR then
		-- Don't RDM T buddies
		if target:GetRole() == self:GetRole() then return false end
	end

	return true
end

--// Checks to see if there is a clear line between the bot's head and the target's head
function plymeta:clearLOS( target )
	local head = target:LookupBone("ValveBiped.Bip01_Head1")
	if head != nil then
		local headpos = target:GetBonePosition(head)
		
		local pos = self:GetShootPos()
		local ang = (headpos - self:GetShootPos()):Angle()
		local tracedata = {}
		tracedata.start = pos
		tracedata.filter = {self}
		tracedata.endpos = target:GetShootPos() + ang:Forward() * 10000 
		local trace = util.TraceLine(tracedata)
		
		if IsValid( trace.Entity ) and trace.Entity == target then
			return true
		end
	end
	return false
end

--// Searches the world to try to find weapons to pick up
function plymeta:findWeapon()
	local cmd = self.cmd
	local weps = {}
	
	-- Locate all weapons that are lying on the ground
	for _, ent in pairs( ents.GetAll() ) do
		if ent:IsWeapon() and not IsValid( ent:GetOwner() ) then
			table.insert( weps, ent )
		end
	end
	
	local closestDist = 100000
	local closestKey = 0
	for k, wep in pairs( weps ) do
		if tttBot.weaponIsValid( wep ) then
			local dist = self:GetPos():Distance( wep:GetPos() )
			
			if dist < closestDist then
				--if self:GetEyeTrace().Entity == wep then
					closestDist = dist
					closestKey = k
				--end
			end
		end
	end
	
	if IsValid( weps[closestKey] ) then
		self:setNewPos( weps[closestKey]:GetPos() )
	end
	
	return weps[closestKey]
end

--// Makes the bot attack
function plymeta:attackTarget()
	local cmd = self.cmd
	
	cmd:SetButtons(IN_ATTACK)
end

--// Selects the bot's crowbar
function plymeta:selectCrowbar()
	local cmd = self.cmd
	
	local crowbar = self:GetWeapon("weapon_zm_improvised")
	
	if IsValid( crowbar ) then
		cmd:SelectWeapon( crowbar )
	end
	
	--[[
	for _, v in pairs( self:GetWeapons() ) do
		if v:GetClass() == "weapon_zm_improvised" then
			cmd:SelectWeapon( v )
		end
	end]]
end

--// Tells the bot to select the first weapon it has or the weapon that matches the class
function plymeta:selectGun( class )
	local cmd = self.cmd
	
	if class then
		-- Find the weapon that matches the class given
		local wep = self:GetWeapon(class)
	
		if IsValid( wep ) then
			cmd:SelectWeapon( wep )
			return true
		end
		return false
	end
	
	-- Select the first weapon we find
	for _, v in pairs( self:GetWeapons() ) do
		if tttBot.weaponIsNotDefault( v ) then
			cmd:SelectWeapon( v )
		end
	end
	
	return true
end

--// Returns true if the bot has a gun with ammo
function plymeta:hasGuns()
	local cmd = self.cmd
	
	for _, v in pairs( self:GetWeapons() ) do
		if tttBot.weaponIsNotDefault( v ) then
			if v:Ammo1() > 0 or v:Clip1() > 0 then
				return true
			end
		end
	end
end