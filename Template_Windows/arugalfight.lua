require "math"
file = io.open("output.txt", "w")
io.output(file)
local slope_threshold = 0.2 -- How much slopeiness will cause character to slide down instead of standing on it
local gravity = -30

local scene = GetScene()

local Layers = {
	Player = 1 << 0,
	NPC = 1 << 1,
}

local States = {
	IDLE = "idle",
	WALK = "walk",
	JOG = "jog",
	RUN = "run",
	JUMP = "jump",
	JUMP_END = "jump_end",
	JUMP_LAND_RUN = "jump_land_run",
	JUMP_START = "jump_start",
	DANCE = "dance",
	WAVE = "wave",
	CAST = "cast",
	SHUFFLE_LEFT = "shuffle_left",
	SHUFFLE_RIGHT = "shuffle_right",
	CASTING = "casting"
}
local character_capsules = {}
local voxelgrid = VoxelGrid(128,32,128)
voxelgrid.SetVoxelSize(0.25)
voxelgrid.SetCenter(Vector(0,0.1,0))
local animations = {}
local function LoadAnimations()
	local troll_entity = scene.Entity_FindByName("makingtrollcoolnoshouulders.glb")
	local anim_scene = scene
	animations = {
		IDLE = anim_scene.Entity_FindByName("Stand (ID 0 variation 0)", troll_entity),
		WALK = anim_scene.Entity_FindByName("Walk (ID 4 variation 0)", troll_entity),
		JOG = anim_scene.Entity_FindByName("Run (ID 5 variation 0)", troll_entity),
		RUN = anim_scene.Entity_FindByName("Run (ID 5 variation 0)", troll_entity),
		JUMP = anim_scene.Entity_FindByName("Jump (ID 38 variation 0)", troll_entity),
		JUMP_END = anim_scene.Entity_FindByName("JumpEnd (ID 39 variation 0)", troll_entity),
		JUMP_LAND_RUN = anim_scene.Entity_FindByName("JumpLandRun (ID 187 variation 0)", troll_entity),
		JUMP_START = anim_scene.Entity_FindByName("JumpLandRun (ID 37 variation 0)", troll_entity),
		DANCE = anim_scene.Entity_FindByName("EmoteDance (ID 69 variation 0)", troll_entity),
		WAVE = anim_scene.Entity_FindByName("EmoteWave (ID 67 variation 0)", troll_entity),
		CAST = anim_scene.Entity_FindByName("SpellCastDirected (ID 53 variation 0)", troll_entity),
		SHUFFLE_LEFT = anim_scene.Entity_FindByName("ShuffleLeft (ID 11 variation 0)", troll_entity),
		SHUFFLE_RIGHT = anim_scene.Entity_FindByName("ShuffleRight (ID 12 variation 0)", troll_entity),
		CASTING = anim_scene.Entity_FindByName("ReadySpellDirected (ID 51 variation 0)", troll_entity),
	}
end

local ArugalStates = {
	IDLE = "idle",
	CAST = "cast",
	CASTING = "casting",
	BLINK = "blink"
}

local arugalAnimations = {}
local function LoadArugalAnimations()
	local arugal_entity = scene.Entity_FindByName("arugalgain2.glb")
	arugalAnimaions = {
		IDLE = scene.Entity_FindByName("Stand", arugal_entity),
		CAST = scene.Entity_FindByName("Spell Ready", arugal_entity),
		CASTING = scene.Entity_FindByName("Spell Throw", arugal_entity),
		BLINK = scene.Entity_FindByName("Spell 2", arugal_entity),
	}
end

local function Arugal(model_entity, start_position, start_rotation)
	local self = {
		model = INVALID_ENTITY,
		player = INVALID_ENTITY,
		anims = {},
		model_shadowbolt = INVALID_ENTITY,
		stateTimer = 0,

		Create = function(self, model_entity, start_position, start_rotation)
			self.model = model_entity
			self.state = ArugalStates.IDLE
			self.state_prev = self.state

			if scene.Component_GetCollider(self.model) == nil then
				local collider = scene.Component_CreateCollider(self.model)
				self.collider = self.model
				collider.SetCPUEnabled(false)
				collider.SetGPUEnabled(true)
				collider.Shape = ColliderShape.Capsule
				collider.Radius = 0.3
				collider.Offset = Vector(0, collider.Radius, 0)
				collider.Tail = Vector(0, 1.4, 0)
				local head_transform = scene.Component_GetTransform(self.head)
				if head_transform ~= nil then
					collider.Tail = head_transform.GetPosition()
				end
			end
			self.anims[ArugalStates.IDLE] = arugalAnimaions.IDLE
			self.anims[ArugalStates.CAST] = arugalAnimaions.CAST
			self.anims[ArugalStates.CASTING] =  arugalAnimaions.CASTING
			self.anims[ArugalStates.BLINK] = arugalAnimaions.BLINK
			local model_transform = scene.Component_GetTransform(self.model)
			model_transform.ClearTransform()
			model_transform.Scale(Vector(0.025, 0.025, 0.025))
			model_transform.Rotate(start_rotation)
			model_transform.Translate(start_position)
			model_transform.UpdateTransform()

			self.model_shadowbolt = scene.Entity_FindByName("shadowbolt.glb")
		end,
		spawn_effect_shadowbolt = function(self, pos, rot, velocity)
			local active_shadowbolt = scene.Entity_Duplicate(self.model_shadowbolt)
			local shadowbolt_animation_entity = scene.Entity_FindByName("Stand (ID 0 variation 0)", active_shadowbolt)
			local shadowbolt_animation = scene.Component_GetAnimation(shadowbolt_animation_entity)

			shadowbolt_animation.SetLooped(true)
			shadowbolt_animation.SetEnd(0.66)
			shadowbolt_animation.Play()
			local transform_component = scene.Component_GetTransform(active_shadowbolt)
			transform_component.ClearTransform()
			--transform_component.Rotate(self.rotation)
			transform_component.Rotate(rot)
			--transform_component.RotateY(rot2)
			transform_component.Translate(pos)
			transform_component.UpdateTransform()
			runProcess(function()
				local alive = true

				for i=1,500,1 do -- move the fireball effect for some frames
					local capsule = scene.Component_GetCollider(active_shadowbolt).GetCapsule()
					local transform_component = scene.Component_GetTransform(active_shadowbolt)
					local o2, p2, n2, depth = scene.Intersects(capsule, FILTER_NAVIGATION_MESH | FILTER_COLLIDER)
					if(o2 ~= INVALID_ENTITY) then
						break
						alive = false
					else
						transform_component.Translate(velocity)
						transform_component.UpdateTransform()
					end
					waitSignal("subprocess_update" .. self.model)
				end
				
				shadowbolt_animation.Stop()
				scene.Component_GetEmitter(active_shadowbolt).SetEmitCount(0)
				local shadowbolt_entity = scene.Entity_FindByName("deathcoil_missile_Geoset0", active_shadowbolt)
				local shadowbolt_object = scene.Component_GetObject(shadowbolt_entity)
				shadowbolt_object.SetRenderable(false)
				scene.Entity_Remove(active_shadowbolt)

			end)
		end,

		SetPlayer = function(self, player)
			self.player = player
		end,

		Update = function(self)

			local dt = getDeltaTime()
			self.stateTimer = dt + self.stateTimer
			if self.state == ArugalStates.IDLE then
				if self.stateTimer > 1 then
					self.stateTimer = 0
					self.state = ArugalStates.CASTING
				end
			elseif self.state == ArugalStates.CASTING then
				if self.stateTimer > 2 then
					self.stateTimer = 0
					self.state = ArugalStates.CAST
					local model_transform = scene.Component_GetTransform(self.model)
					local player_transform = scene.Component_GetTransform(self.player)
					local model_pos = model_transform.GetPosition()
					local player_pos = player_transform.GetPosition()
					local vector_line = player_pos:Subtract(model_pos)
					local dir = vector.Normalize(vector_line)
					local angle = -math.atan(dir.GetZ(), dir.GetX() )
					local angle2 = math.asin(dir.GetY() )
					local shadowbolt_speed = 0.2
					self:spawn_effect_shadowbolt(vector.Add(model_transform.GetPosition(), Vector(0, 1.4)), Vector(0,angle, angle2), dir:Multiply(Vector(shadowbolt_speed,shadowbolt_speed,shadowbolt_speed)))
				end
			end
			local current_anim = scene.Component_GetAnimation(self.anims[self.state])
			if current_anim ~= nil then
				-- Play current anim:
				current_anim.SetLooped(true)
				current_anim.Play()
				if self.state_prev ~= self.state then
					-- If anim just started in this frame, reset timer to beginning:
					current_anim.SetTimer(current_anim.GetStart())
					self.state_prev = self.state
				end
				
				-- Simple state transition to idle:
				if self.state == States.CAST then
					if current_anim.GetTimer() > current_anim.GetEnd() then
						self.state = States.IDLE
					end
				end
			end
		end,
		UpdateShadowbolt = function(self)
			signal("subprocess_update" .. self.model)
		end,

	}
	self:Create(model_entity, start_position, start_rotation)
	return self
end

local function Character(model_entity, start_position, face, controllable, anim_scene)
	local self = {
		model = INVALID_ENTITY,
		target_rot_horizontal = 0,
		target_rot_vertical = 0,
		frostbolt_rot_vertical = 0,
		char_rot_horizontal = 0,
		target_height = 0,
		anims = {},
		anim_amount = 1,
		neck = INVALID_ENTITY,
		head = INVALID_ENTITY,
		left_hand = INVALID_ENTITY,
		right_hand = INVALID_ENTITY,
		left_foot = INVALID_ENTITY,
		right_foot = INVALID_ENTITY,
		left_toes = INVALID_ENTITY,
		right_toes = INVALID_ENTITY,
		face = Vector(0,0,1), -- forward direction (smoothed)
		face_next = Vector(0,0,1), -- forward direction in current frame
		movement_velocity = Vector(),
		velocity = Vector(),
		savedPointerPos = Vector(),
		walk_speed = 0.3,
		jog_speed = 0.6,
		run_speed = 0.6,
		jump_speed = 18,
		frostbolt_speed = 0.1,
		layerMask = ~0, -- layerMask will be used to filter collisions
		scale = Vector(1, 1, 1),
		rotation = Vector(0,-math.pi/2,0),
		start_position = Vector(0, 1, 0),
		position = Vector(),
		controllable = true,
		fixed_update_remain = 0,
		timestep_occured = false,
		root_bone_offset = 0,
		foot_placed_left = false,
		foot_placed_right = false,
		jump_check = false,
		model_frostbolt = INVALID_ENTITY,
		active_frostbolt = INVALID_ENTITY,
		arugal_model = INVALID_ENTITY,
		camera = nil,
		casting = false,
		frostbolt_sound = nil,
		frostbolt_sound_instance = nil,
		sound = Sound(),
		soundinstance = SoundInstance(),
		state = States.IDLE,
		state_prev = States.IDLE,
		
		Create = function(self, model_entity, start_position, face, controllable)
			self.start_position = start_position
			self.face = face
			self.face_next = face
			self.controllable = controllable
			if controllable then
				self.layerMask = Layers.Player
			else
				self.layerMask = Layers.NPC
			end
			self.model = model_entity
			local layer = scene.Component_CreateLayer(self.model)
			layer.SetLayerMask(self.layerMask)

			self.state = States.IDLE
			self.state_prev = self.state

			local humanoid = scene.Component_CreateHumanoid(model_entity)
			self.frostbolt_sound = Sound(script_dir() .. "precastfrostmagiclow.wav")
			self.frostbolt_sound_instance = SoundInstance(frostbolt_sound)
			self.frostbolt_sound_instance:SetLooped(true)
			self.model_frostbolt = scene.Entity_FindByName("FINDME")

			self.arugal_model = scene.Entity_FindByName("arugalgain2.glb")

			local neckBone = anim_scene.Entity_FindByName("bone_Neck", model_entity)
			self.neck = humanoid.SetBoneEntity(HumanoidBone.Neck, neckBone)
			local headBone = anim_scene.Entity_FindByName("bone_Head", model_entity)
			self.head = humanoid.SetBoneEntity(HumanoidBone.Head, headBone)
			local leftHandBone = anim_scene.Entity_FindByName("bone_HandL", model_entity)
			self.left_hand = humanoid.SetBoneEntity(HumanoidBone.LeftHand, leftHandBone)
			local rightHandBone = anim_scene.Entity_FindByName("bone_HandR", model_entity)
			self.right_hand = humanoid.SetBoneEntity(HumanoidBone.RightHand, rightHandBone)
			local leftFootBone = anim_scene.Entity_FindByName("bone_FootL", model_entity)
			self.left_foot = humanoid.SetBoneEntity(HumanoidBone.LeftFoot, leftFootBone)
			self.left_toes = humanoid.SetBoneEntity(HumanoidBone.LeftToes, leftFootBone)
			local rightFootBone = anim_scene.Entity_FindByName("bone_FootR", model_entity)
			self.right_foot = humanoid.SetBoneEntity(HumanoidBone.RightFoot, rightFootBone)
			self.right_toes = humanoid.SetBoneEntity(HumanoidBone.RightToes, rightFootBone)
			local spineBone = anim_scene.Entity_FindByName("bone_SpineUp", model_entity)
			humanoid.SetBoneEntity(HumanoidBone.Spine, spineBone)
			local hips = anim_scene.Entity_FindByName("bone_Waist", model_entity)
			humanoid.SetBoneEntity(HumanoidBone.Hips, hips)
			local leftLegBone = anim_scene.Entity_FindByName("bone_LegL", model_entity)
			humanoid.SetBoneEntity(HumanoidBone.LeftUpperLeg, leftLegBone)
			humanoid.SetBoneEntity(HumanoidBone.LeftLowerLeg, leftLegBone)
			local rightLegBone = anim_scene.Entity_FindByName("bone_LegR", model_entity)
			humanoid.SetBoneEntity(HumanoidBone.RightUpperLeg, rightLegBone)
			humanoid.SetBoneEntity(HumanoidBone.RightLowerLeg, rightLegBone)
			local rightUpperArmBone = anim_scene.Entity_FindByName("bone_ArmR", model_entity)
			humanoid.SetBoneEntity(HumanoidBone.RightUpperArm, rightUpperArmBone)
			local rightLowerArmBone = anim_scene.Entity_FindByName("bone_ForearmR", model_entity)
			humanoid.SetBoneEntity(HumanoidBone.RightLowerArm, rightLowerArmBone)
			local leftUpperArmBone = anim_scene.Entity_FindByName("bone_ArmL", model_entity)
			humanoid.SetBoneEntity(HumanoidBone.LeftUpperArm, leftUpperArmBone)
			local leftLowerArmBone = anim_scene.Entity_FindByName("bone_ForearmL", model_entity)
			humanoid.SetBoneEntity(HumanoidBone.LeftLowerArm, leftLowerArmBone)

			-- Create a base capsule collider if it's not yet configured for character:
			--	It will be used for movement logic and GPU collision effects
			if scene.Component_GetCollider(self.model) == nil then
				local collider = scene.Component_CreateCollider(self.model)
				self.collider = self.model
				collider.SetCPUEnabled(false)
				collider.SetGPUEnabled(true)
				collider.Shape = ColliderShape.Capsule
				collider.Radius = 0.3
				collider.Offset = Vector(0, collider.Radius, 0)
				collider.Tail = Vector(0, 1.4, 0)
				local head_transform = scene.Component_GetTransform(self.head)
				if head_transform ~= nil then
					collider.Tail = head_transform.GetPosition()
				end
			else
				self.collider = self.humanoid
			end

			self.root = scene.Entity_FindByName("Root", self.model)

			self.anims[States.IDLE] = animations.IDLE
			self.anims[States.WALK] = animations.WALK
			self.anims[States.JOG] =  animations.JOG
			self.anims[States.RUN] = animations.RUN
			self.anims[States.JUMP] =  animations.JUMP
			self.anims[States.JUMP_END] =  animations.JUMP_END
			self.anims[States.JUMP_LAND_RUN] = animations.JUMP_LAND_RUN
			self.anims[States.JUMP_START] =  animations.JUMP_START
			self.anims[States.DANCE] = animations.DANCE
			self.anims[States.WAVE] = animations.WAVE
			self.anims[States.CAST] = animations.CAST
			self.anims[States.SHUFFLE_LEFT] = animations.SHUFFLE_LEFT
			self.anims[States.SHUFFLE_RIGHT] = animations.SHUFFLE_RIGHT
			self.anims[States.CASTING] = animations.CASTING

			local model_transform = scene.Component_GetTransform(self.model)
			model_transform.ClearTransform()
			model_transform.Scale(self.scale)
			model_transform.Rotate(self.rotation)
			model_transform.Translate(self.start_position)
			model_transform.UpdateTransform()
			self.target_height = 1.5--scene.Component_GetTransform(self.neck).GetPosition().GetY()

		end,
		spawn_effect_frostbolt = function(self, pos, rot, velocity)
			local active_frostbolt = scene.Entity_Duplicate(self.model_frostbolt)
			local frostbolt_animation_entity = scene.Entity_FindByName("Stand (ID 0 variation 0)", active_frostbolt)
			local frostbolt_animation = scene.Component_GetAnimation(frostbolt_animation_entity)

			frostbolt_animation.SetLooped(true)
			frostbolt_animation.SetEnd(0.66)
			frostbolt_animation.Play()
			local transform_component = scene.Component_GetTransform(active_frostbolt)
			transform_component.ClearTransform()
			--transform_component.Rotate(self.rotation)
			transform_component.Rotate(rot)
			--transform_component.RotateY(rot2)
			transform_component.Translate(pos)
			transform_component.UpdateTransform()
			runProcess(function()
				local alive = true

				for i=1,500,1 do -- move the fireball effect for some frames
					local capsule = scene.Component_GetCollider(active_frostbolt).GetCapsule()
					local transform_component = scene.Component_GetTransform(active_frostbolt)
					local o2, p2, n2, depth = scene.Intersects(capsule, FILTER_NAVIGATION_MESH | FILTER_COLLIDER)
					if(o2 ~= INVALID_ENTITY) then
						break
						alive = false
					else
						transform_component.Translate(velocity)
						transform_component.UpdateTransform()
					end
					waitSignal("subprocess_update" .. self.model)
				end
				
				frostbolt_animation.Stop()
				scene.Component_GetEmitter(active_frostbolt).SetEmitCount(0)
				local frostbolt_entity = scene.Entity_FindByName("frostbolt_Geoset1", active_frostbolt)
				local frostbolt_object = scene.Component_GetObject(frostbolt_entity)
				frostbolt_object.SetRenderable(false)
				scene.Entity_Remove(active_frostbolt)

			end)
		end,

		Jump = function(self,f)
			self.velocity.SetY(f)
			self.state = States.JUMP
			self.jump_check = false
		end,
		MoveDirection = function(self,dir)
			local rotation_matrix = matrix.Multiply(matrix.RotationY(self.target_rot_horizontal), matrix.RotationX(self.target_rot_vertical))
			dir = vector.Transform(dir.Normalize(), rotation_matrix)
			dir.SetY(0)
			local dot = vector.Dot(self.face, dir)
			if(dot < 0) then
				self.face = vector.TransformNormal(self.face, matrix.RotationY(math.pi * 0.01)) -- Turn around 180 degrees easily when wanting to go backwards
			end
			self.face_next = dir
			self.face_next = self.face_next.Normalize()
			if(dot > 0) then 
				local speed = 0
				if self.state == States.WALK then
					speed = self.walk_speed
				elseif self.state == States.JOG then
					speed = self.jog_speed
				elseif self.state == States.RUN then
					speed = self.run_speed
				end
				self.movement_velocity = self.face:Multiply(Vector(speed,speed,speed))
			end

		end,

		Update = function(self)

			local dt = getDeltaTime()

			--local humanoid = scene.Component_GetHumanoid(self.humanoid)
			--humanoid.SetLookAtEnabled(false)

			local model_transform = scene.Component_GetTransform(self.model)
			local savedPos = model_transform.GetPosition()
			model_transform.ClearTransform()
			--model_transform.MatrixTransform(matrix.LookTo(Vector(),self.face):Inverse())
			model_transform.Scale(self.scale)
			model_transform.Rotate(self.rotation)
			model_transform.Rotate(Vector(0, self.char_rot_horizontal))
			model_transform.Translate(savedPos)
			model_transform.UpdateTransform()
			
			if self.controllable then
				-- Camera target control:

				-- read from gamepad analog stick:
				local diff = input.GetAnalog(GAMEPAD_ANALOG_THUMBSTICK_R)
				diff = vector.Multiply(diff, dt * 4)
				
				-- read from mouse:
				if(input.Down(MOUSE_BUTTON_RIGHT)) then
					local mouseDif = input.GetPointerDelta()
					mouseDif = mouseDif:Multiply(dt * 0.3)
					diff = vector.Add(diff, mouseDif)
					input.SetPointer(self.savedPointerPos)
					input.HidePointer(true)
				else
					self.savedPointerPos = input.GetPointer()
					input.HidePointer(false)
				end

				if (input.Press(MOUSE_BUTTON_LEFT) and (not self.casting)) then
					--audio.SetVolume(0.5)
					--audio.Play(self.frostbolt_sound_instance)
					audio.Stop(self.soundinstance)
					audio.CreateSound(script_dir() .. "precastfrostmagiclow.ogg", self.sound)
					audio.CreateSoundInstance(self.sound, self.soundinstance)
					self.soundinstance.SetLooped(false)
					audio.SetVolume(0.5, self.soundinstance)
					audio.Play(self.soundinstance)
					
					self.casting = true
					self.controllable = false
					self.state = States.CASTING
					local file = io.open("anim", "w")
					file:write("CASTING\n")
					io.close(file)
				end
				if (input.Release(MOUSE_BUTTON_LEFT)) then
					--audio.Stop(self.frostbolt_sound_instance)
					audio.Stop(self.soundinstance)
					self.state = States.IDLE
					self.casting = false
					self.controllable = true
				end
				if (input.Hold(MOUSE_BUTTON_LEFT, 100)) then
					--audio.Stop(self.frostbolt_sound_instance)
					audio.Stop(self.soundinstance)
					audio.CreateSound(script_dir() .. "icecast.ogg", self.sound)
					audio.CreateSoundInstance(self.sound, self.soundinstance)
					self.soundinstance.SetLooped(false)
					audio.SetVolume(0.5, self.soundinstance)
					audio.Play(self.soundinstance)
					self.state = States.CAST
					local frostbolt_speed = self.frostbolt_speed
					local camera_transform = scene.Component_GetTransform(self.camera.camera)
					local camera_component = GetCamera()
					local bestLookDir = camera_component.GetLookDirection()

					local angle = -math.atan(bestLookDir.GetZ(), bestLookDir.GetX() )

					local angle2 =  math.asin(bestLookDir.GetY() )
					self:spawn_effect_frostbolt(vector.Add(model_transform.GetPosition(), Vector(0, 1.4)), Vector(0,angle, angle2), bestLookDir:Multiply(Vector(frostbolt_speed,frostbolt_speed,frostbolt_speed)))
					self.casting = false
					self.controllable = true
				end
				
				self.target_rot_horizontal = self.target_rot_horizontal + diff.GetX()
				if (input.Down(MOUSE_BUTTON_RIGHT)) then
					self.char_rot_horizontal = self.char_rot_horizontal + diff.GetX()
				end
				self.target_rot_vertical = math.clamp(self.target_rot_vertical + diff.GetY(), -math.pi * 0.3, math.pi * 0.4) -- vertical camers limits
				self.frostbolt_rot_vertical = self.frostbolt_rot_vertical + diff.GetY()
			end

			-- state and animation update
			local current_anim = scene.Component_GetAnimation(self.anims[self.state])
			if current_anim ~= nil then
				-- Play current anim:
				current_anim.SetLooped(true)
				current_anim.Play()
				if self.state_prev ~= self.state then
					-- If anim just started in this frame, reset timer to beginning:
					current_anim.SetTimer(current_anim.GetStart())
					self.state_prev = self.state
				end
				
				-- Simple state transition to idle:
				if self.state == States.JUMP_START then
					if current_anim.GetTimer() > current_anim.GetEnd() then
						self.state = States.JUMP
					end
				elseif self.state == States.JUMP then
					if self.velocity.GetY() < 0 then
						self.jump_check = true
					elseif self.velocity.GetY() == 0 and self.jump_check then
						self.state = States.JUMP_END
					end
				elseif self.state == States.JUMP_END then
					if current_anim.GetTimer() > current_anim.GetEnd() then
						self.state = States.IDLE
					end
				elseif self.state == States.CAST then
					if current_anim.GetTimer() > current_anim.GetEnd() then
						self.state = States.IDLE
					end
				else
					if self.velocity.Length() < 0.1 and self.state ~= States.SWIM_IDLE and self.state ~= States.SWIM and self.state ~= States.DANCE and self.state ~= States.WAVE and self.state ~= States.CASTING then
						self.state = States.IDLE
					end
				end
			end

			if dt > 0.2 then
				return -- avoid processing too large delta times to avoid instability
			end

			if self.controllable then
				if not backlog_isactive() then
					-- Movement input:
					local lookDir = Vector()
					if(input.Down(KEYBOARD_BUTTON_LEFT) or input.Down(string.byte('A'))) then
						lookDir = lookDir:Add( Vector(-1) )
					end
					if(input.Down(KEYBOARD_BUTTON_RIGHT) or input.Down(string.byte('D'))) then
						lookDir = lookDir:Add( Vector(1) )
					end
					
					if(input.Down(KEYBOARD_BUTTON_UP) or input.Down(string.byte('W'))) then
						lookDir = lookDir:Add( Vector(0,0,1) )
					end
					if(input.Down(KEYBOARD_BUTTON_DOWN) or input.Down(string.byte('S'))) then
						lookDir = lookDir:Add( Vector(0,0,-1) )
					end

					local analog = input.GetAnalog(GAMEPAD_ANALOG_THUMBSTICK_L)
					lookDir = vector.Add(lookDir, Vector(analog.GetX(), 0, analog.GetY()))
						
					if self.state ~= States.JUMP and self.state_prev ~= States.JUMP and self.velocity.GetY() == 0 then
						if(lookDir.Length() > 0) then
							if(input.Down(KEYBOARD_BUTTON_LSHIFT) or input.Down(GAMEPAD_BUTTON_6)) then
								if input.Down(string.byte('E')) or input.Down(GAMEPAD_BUTTON_5) then
									self.state = States.RUN
									self:MoveDirection(lookDir)
								else
									self.state = States.JOG
									self:MoveDirection(lookDir)
								end
							else
								self.state = States.WALK
								self:MoveDirection(lookDir)
							end
						end
						
						if(input.Press(string.byte('J')) or input.Press(KEYBOARD_BUTTON_SPACE) or input.Press(GAMEPAD_BUTTON_3)) then
							self:Jump(self.jump_speed)
						end
					elseif self.velocity.GetY() > 0 then
						self:MoveDirection(lookDir)
					end
				end
			end

			-- Capsule collision for character:
			local capsule = scene.Component_GetCollider(self.collider).GetCapsule()
			local original_capsulepos = model_transform.GetPosition()
			local capsulepos = original_capsulepos
			local capsuleheight = vector.Subtract(capsule.GetTip(), capsule.GetBase()).Length()
			local radius = capsule.GetRadius()
			local collision_layer = ~self.layerMask
			if not controllable and not allow_pushaway_NPC then
				-- For NPC, this makes it not pushable away by player:
				--	This works by disabling NPC's collision to player
				--	But the player can still collide with NPC and can be blocked
				collision_layer = collision_layer & ~Layers.Player
			end
			local current_anim = scene.Component_GetAnimation(self.anims[self.state])
			local platform_velocity_accumulation = Vector()
			local platform_velocity_count = 0

			-- Perform fixed timestep logic:
			self.fixed_update_remain = self.fixed_update_remain + dt
			local fixed_update_fps = 300
			local fixed_dt = 1.0 / fixed_update_fps
			self.timestep_occured = false

			while self.fixed_update_remain >= fixed_dt do
				self.timestep_occured = true;
				self.fixed_update_remain = self.fixed_update_remain - fixed_dt
				
				if swimming then
					self.velocity = vector.Multiply(self.velocity, 0.8) -- water friction
				end
				if self.velocity.GetY() > -30 then
					self.velocity = vector.Add(self.velocity, Vector(0, gravity * fixed_dt, 0)) -- gravity
				end
				self.velocity = vector.Add(self.velocity, self.movement_velocity)

				capsulepos = vector.Add(capsulepos, vector.Multiply(self.velocity, fixed_dt))
				capsule = Capsule(capsulepos, vector.Add(capsulepos, Vector(0, capsuleheight)), radius)
				local o2, p2, n2, depth, platform_velocity = scene.Intersects(capsule, FILTER_NAVIGATION_MESH | FILTER_COLLIDER, collision_layer) -- scene/capsule collision
				if(o2 ~= INVALID_ENTITY) then

					--if debug then
					--	DrawPoint(p2,0.1,Vector(1,1,0,1))
					--	DrawLine(p2, vector.Add(p2, n2), Vector(1,1,0,1))
					--end

					local ground_slope = vector.Dot(n2, Vector(0,1,0))

					if ground_slope > slope_threshold then
						-- Ground intersection:
						self.velocity = vector.Multiply(self.velocity, 0.92) -- ground friction
						capsulepos = vector.Add(capsulepos, Vector(0, depth, 0)) -- avoid sliding, instead stand upright
						platform_velocity_accumulation = vector.Add(platform_velocity_accumulation, platform_velocity)
						platform_velocity_count = platform_velocity_count + 1
						self.velocity.SetY(0)
					else
						-- Slide on contact surface:
						local velocityLen = self.velocity.Length()
						local velocityNormalized = self.velocity.Normalize()
						local undesiredMotion = n2:Multiply(vector.Dot(velocityNormalized, n2))
						local desiredMotion = vector.Subtract(velocityNormalized, undesiredMotion)
						self.velocity = vector.Multiply(desiredMotion, velocityLen)
						capsulepos = vector.Add(capsulepos, vector.Multiply(n2, depth))
					end
				end

				-- Some other things also updated at fixed rate:
				self.face = vector.Lerp(self.face, self.face_next, 0.1) -- smooth the turning in fixed update
				self.face.SetY(0)
				self.face = self.face.Normalize()

				-- Animation blending
				if current_anim ~= nil then
					-- Blend in current animation:
					current_anim.SetAmount(math.lerp(current_anim.GetAmount(), self.anim_amount, 0.1))
					
					-- Ease out other animations:
					for i,anim in pairs(self.anims) do
						if (anim ~= INVALID_ENTITY) and (anim ~= self.anims[self.state]) then
							local prev_anim = scene.Component_GetAnimation(anim)
							prev_anim.SetAmount(math.lerp(prev_anim.GetAmount(), 0, 0.1))
							if prev_anim.GetAmount() <= 0 then
								prev_anim.Stop()
							end
						end
					end
				end
			end

			if platform_velocity_count > 0 then
				capsulepos = vector.Add(capsulepos, vector.Multiply(platform_velocity_accumulation, 1.0 / platform_velocity_count)) -- apply moving platform velocity
			end

			model_transform.Translate(vector.Subtract(capsulepos, original_capsulepos)) -- transform by the capsule offset
			model_transform.UpdateTransform()

			self.movement_velocity = Vector()

			character_capsules[self.model] = capsule
			self.position = model_transform.GetPosition()

			-- If camera is inside character capsule, fade out the character, otherwise fade in:
			if capsule.Intersects(GetCamera().GetPosition()) then
				for i,entity in ipairs(scene.Entity_GetObjectArray()) do
					if scene.Entity_IsDescendant(entity, self.model) then
						local object = scene.Component_GetObject(entity)
						local color = object.GetColor()
						local opacity = color.GetW()
						opacity = math.lerp(opacity, 0, 0.1)
						color.SetW(opacity)
						object.SetColor(color)
					end
				end
			else
				for i,entity in ipairs(scene.Entity_GetObjectArray()) do
					if scene.Entity_IsDescendant(entity, self.model) then
						local object = scene.Component_GetObject(entity)
						local color = object.GetColor()
						local opacity = color.GetW()
						opacity = math.lerp(opacity, 1, 0.1)
						color.SetW(opacity)
						object.SetColor(color)
					end
				end
			end
		end,
		UpdateFrostbolt = function(self)
			signal("subprocess_update" .. self.model)
		end,

	}

	self:Create(model_entity, start_position, face, controllable)
	return self
end

local function ThirdPersonCamera(character)
	local self = {
		camera = INVALID_ENTITY,
		character = nil,
		side_offset = 1,
		rest_distance = 1,
		rest_distance_new = 1,
		min_distance = 0.5,
		zoom_speed = 0.3,
		target_rot_horizontal = 0,
		target_rot_vertical = 0,
		target_height = 0,
		
		Create = function(self, character)
			self.character = character
			character.camera = self
			self.camera = CreateEntity()
			local camera_transform = scene.Component_CreateTransform(self.camera)
		end,
		
		Update = function(self)
			if self.character == nil then
				return
			end

			-- Mouse scroll or gamepad triggers will move the camera distance:
			local scroll = input.GetPointer().GetZ() -- pointer.z is the mouse wheel delta this frame
			scroll = scroll + input.GetAnalog(GAMEPAD_ANALOG_TRIGGER_R).GetX()
			scroll = scroll - input.GetAnalog(GAMEPAD_ANALOG_TRIGGER_L).GetX()
			scroll = scroll * self.zoom_speed
			self.rest_distance_new = math.max(self.rest_distance_new - scroll, self.min_distance) -- do not allow too close using max
			self.rest_distance = math.lerp(self.rest_distance, self.rest_distance_new, 0.1) -- lerp will smooth out the zooming

			-- This will allow some smoothing for certain movements of camera target:
			local character_transform = scene.Component_GetTransform(self.character.model)
			local character_position = character_transform.GetPosition()
			self.target_rot_horizontal = math.lerp(self.target_rot_horizontal, self.character.target_rot_horizontal, 0.1)
			self.target_rot_vertical = math.lerp(self.target_rot_vertical, self.character.target_rot_vertical, 0.1)
			self.target_height = math.lerp(self.target_height, character_position.GetY() + self.character.target_height, 0.1)

			local camera_transform = scene.Component_GetTransform(self.camera)
			local target_transform = TransformComponent()
			target_transform.Translate(Vector(character_position.GetX(), self.target_height, character_position.GetZ()))
			--target_transform.Translate(Vector(0, self.target_height))
			target_transform.Rotate(Vector(self.target_rot_vertical, self.target_rot_horizontal))
			target_transform.UpdateTransform()
			
			-- First calculate the rest orientation (transform) of the camera:
			local mat = matrix.Translation(Vector(self.side_offset, 0, -self.rest_distance))
			mat = matrix.Multiply(mat, target_transform.GetMatrix())
			camera_transform.ClearTransform()
			camera_transform.MatrixTransform(mat)
			camera_transform.UpdateTransform()


			-- Camera collision:

			-- Compute the relation vectors between camera and target:
			local camPos = camera_transform.GetPosition()
			local targetPos = target_transform.GetPosition()
			local camDistance = vector.Subtract(camPos, targetPos).Length()

			-- These will store the closest collision distance and required camera position:
			local bestDistance = camDistance
			local bestPos = camPos
			local camera = GetCamera()

			-- Update global camera matrices for rest position:
			camera.TransformCamera(camera_transform)
			camera.UpdateCamera()

			-- Cast rays from target to clip space points on the camera near plane to avoid clipping through objects:
			local unproj = camera.GetInvViewProjection()	-- camera matrix used to unproject from clip space to world space
			local clip_coords = {
				Vector(0,0,1,1),	-- center
				Vector(-1,-1,1,1),	-- bottom left
				Vector(-1,1,1,1),	-- top left
				Vector(1,-1,1,1),	-- bottom right
				Vector(1,1,1,1),	-- top right
			}
			for i,coord in ipairs(clip_coords) do
				local corner = vector.TransformCoord(coord, unproj)
				local target_to_corner = vector.Subtract(corner, targetPos)
				local corner_to_campos = vector.Subtract(camPos, corner)
				local TMin = 0
				local TMax = target_to_corner.Length() -- optimization: limit the ray tracing distance

				local ray = Ray(targetPos, target_to_corner.Normalize(), TMin, TMax)

				local collision_layer =  ~(Layers.Player | Layers.NPC) -- specifies that neither NPC, nor Player can collide with camera
				local collObj,collPos,collNor = scene.Intersects(ray, FILTER_NAVIGATION_MESH | FILTER_COLLIDER,  collision_layer)
				if(collObj ~= INVALID_ENTITY) then
					-- It hit something, see if it is between the player and camera:
					local collDiff = vector.Subtract(collPos, targetPos)
					local collDist = collDiff.Length()
					if(collDist > 0 and collDist < bestDistance) then
						bestDistance = collDist
						bestPos = vector.Add(collPos, corner_to_campos)
						--DrawPoint(collPos, 0.1, Vector(1,0,0,1))
					end
				end
			end
			
			-- We have the best candidate for new camera position now, so offset the camera with the delta between the old and new camera position:
			local collision_offset = vector.Subtract(bestPos, camPos)
			mat = matrix.Multiply(mat, matrix.Translation(collision_offset))
			camera_transform.ClearTransform()
			camera_transform.MatrixTransform(mat)
			camera_transform.UpdateTransform()
			--DrawPoint(bestPos, 0.1, Vector(1,1,0,1))
			
			-- Feed back camera after collision:
			camera.TransformCamera(camera_transform)
			camera.UpdateCamera()
				
		end,
	}

	self:Create(character)
	return self
end

runProcess(function()
	io.write("START SCRIPT\n")
	local model_scene = GetScene()
	LoadModel(model_scene, script_dir() .. "catastrophe.wiscene")

	local level_entity = model_scene.Entity_FindByName("arugal_fight.glb")
	--[[
	local collider = scene.Component_CreateCollider(level_entity)
	collider.SetCPUEnabled(false)
	collider.SetGPUEnabled(true)
	collider.Shape = ColliderShape.Plane
	collider.Radius = 0.3
	collider.Offset = Vector(0, collider.Radius, 0)
	collider.Tail = Vector(0, 1.4, 0)
	--]]
	--scene.VoxelizeScene(voxelgrid, false, FILTER_NAVIGATION_MESH | FILTER_COLLIDER, ~(Layers.Player | Layers.NPC))
	--local weather = model_scene.Component_CreateWeather(level_entity)

	--weather.sunColor = Vector(250,250,210)
	--weather.ambient = Vector(0.7,0.7,0.7)
	--weather.SetSimpleSky(true)
	local music = Sound()
	local musicInstance = SoundInstance()

	audio.CreateSound(script_dir() .. "orgrimmar02-moment.ogg", music)
	audio.CreateSoundInstance(music, musicInstance)
	musicInstance.SetSubmixType(SUBMIX_TYPE_MUSIC) 
	audio.SetVolume(0.3, musicInstance)
	audio.Play(musicInstance)
	


	local troll_entity = model_scene.Entity_FindByName("makingtrollcoolnoshouulders.glb")
	LoadAnimations()
	local arugal_entity = model_scene.Entity_FindByName("arugalgain2.glb")
	LoadArugalAnimations()
	local player = Character(troll_entity, Vector(0,0.5,0), Vector(0,0,1), true, model_scene)
	local arugal = Arugal(arugal_entity, Vector(-14, 11, 2.79), Vector(0,0,0))
	arugal:SetPlayer(troll_entity)
	local camera = ThirdPersonCamera(player)

	local musicTimer = 0

	while true do

		player:Update()
		arugal:Update()
		-- Hierarchy after character positioning is updated, this is needed to place camera and IK afterwards to most up to date locations
		--	But we do it once, not every character!
		scene.UpdateHierarchy()
		--player:Update_IK()
		player:UpdateFrostbolt()
		arugal:UpdateShadowbolt()

		player.controllable = true

		camera:Update()

		update()

		local dt = getDeltaTime()
		musicTimer = dt + musicTimer
		if musicTimer > 63 then
			musicTimer = 0
			
			audio.Stop(musicInstance)
			--[[music = Sound()
			musicInstance = SoundInstance()
			audio.CreateSound(script_dir() .. "orgrimmar02-moment.ogg", music)
			audio.CreateSoundInstance(music, musicInstance)
			musicInstance.SetSubmixType(SUBMIX_TYPE_MUSIC) 
			audio.SetVolume(0.3, musicInstance)
			--]]
			audio.Play(musicInstance)
		end

		if not backlog_isactive() then
			if(input.Press(KEYBOARD_BUTTON_ESCAPE)) then
				-- restore previous component
				--	so if you loaded this script from the editor, you can go back to the editor with ESC
				backlog_post("EXIT")
				for i,anim in ipairs(scene.Component_GetAnimationArray()) do
					anim.Stop() -- stop animations because some of them are retargeted and animation source scene will be lost after we exit this script!
				end
				killProcesses()
				return
			end
		end

	end

end)



--- AFTER IMPORT CODE

--[[

local mousePosition = {}
mousePosition.x = 0
mousePosition.y = 0
mousePosition.engaged = false




runProcess(function()
	while true do
		if not mousePosition.engaged then
			io.write("WAIT CAMERA\n")
			waitSignal("moveCamera")
		end
		local newPosition = input.GetPointer()
		local cameraRotation = Rotation(Vector(0, (newPosition.x - mousePosition.x) * 50, (newPosition.y - mousePosition.y) * 50, 0))
		io.write("CAMERA RUN\n")
		local camera = GetCamera()
		camera.TransformCamera(cameraRotation)
		mousePosition.x = newPosition.x
		mousePosition.y = newPosition.y
		waitSeconds(0.1)
	end

end)

runProcess(function()
	io.write("START SCRIPT\n")
	local model_scene = GetScene()
	LoadModel(model_scene, script_dir() .. "arugalfight.wiscene")

	local troll_entity = model_scene.Entity_FindByName("makingtrollcoolnoshouulders.glb")

	io.write(troll_entity)

	local troll_transform = model_scene.Component_GetTransform(troll_entity)

	if troll_transform then
		io.write("GOT TRANSFORM\n")
		local camera = GetCamera()
		camera.TransformCamera(troll_transform)
	end
	while true do

		if(input.Press(MOUSE_BUTTON_RIGHT)) then
			io.write("GOT RIGHT\n")
			while true do
				local newPosition = input.GetPointer()
				if newPosition.x then
					io.write(newPosition.x)
				end
				waitSeconds(0.1)
			end
			local newPosition = input.GetPointer()
			mousePosition.x = newPosition.x
			mousePosition.y = newPosition.y
			mousePosition.engaged = true
			signal("moveCamera")
		elseif(input.Release(MOUSE_BUTTON_RIGHT)) then
			io.write("RELEASE RIGHT\n")
			mousePosition.engaged = false
		end

		update()

		if(input.Press(KEYBOARD_BUTTON_ESCAPE)) then
			-- restore previous component
			--	so if you loaded this script from the editor, you can go back to the editor with ESC
			backlog_post("EXIT")
			killProcesses()
			return
		end
	end

	io.write("END SCRIPT\n")
end)
--]]
