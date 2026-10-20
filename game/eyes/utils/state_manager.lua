--[[
================================================================================
 eyes/utils/state_manager.lua —— 眼睛场景状态管理器
================================================================================
 作用：
   集中管理眼睛场景的运行时状态，把分散的状态更新收拢到一处，便于维护。
   内部按职责拆分为三个子管理器：
     - motion（运动）    ：维护漂浮动画的时间累加器。
     - interaction（交互）：根据鼠标位置更新每只眼睛的触碰状态。
     - effects（特效）    ：更新瞳孔放大、反光以及整体抖动等视觉效果。

 调用方式：
   由 eyes 主模块在 load 时创建（StateManager.new(eyes)），
   并在每帧 update 中调用 :update(dt) 统一推进所有状态。
================================================================================
--]]

---@class StateManager 负责眼睛模块的集中式状态管理
local StateManager = {}
StateManager.__index = StateManager

---创建一个新的状态管理器
---@param eyes table 眼睛主模块
---@return StateManager
function StateManager.new(eyes)
  local self = setmetatable({}, StateManager)
  self.eyes = eyes
  -- 核心状态
  self.isOnline = false
  self.mousePosition = {x = 0, y = 0}
  self.touching = false
  self.shake = {x = 0, y = 0}

  -- 按逻辑分组创建各子管理器
  self.motion = self:createMotionManager()
  self.interaction = self:createInteractionManager()
  self.effects = self:createEffectsManager()

  return self
end

---创建运动状态子管理器
---@return table 运动状态管理器
function StateManager:createMotionManager()
  return {
    -- 漂浮动画的时间累加器
    timeX = 0,
    timeY = 0,

    -- 更新漂浮时间累加器
    ---@param dt number 帧间隔时间
    ---@param config table 漂浮配置
    updateTime = function(self, dt, config)
      self.timeX = (self.timeX + dt * config.speedX) % (2 * math.pi)
      self.timeY = (self.timeY + dt * config.speedY) % (2 * math.pi)
    end
  }
end

---创建交互状态子管理器
---@return table 交互状态管理器
function StateManager:createInteractionManager()
  return {
    -- 根据鼠标位置更新触碰状态
    ---@param eyes table 眼睛集合
    ---@param mouseX number 鼠标 X 位置
    ---@param mouseY number 鼠标 Y 位置
    ---@param dt number 帧间隔时间
    ---@param fadeSpeed number 颜色渐变速度
    updateTouchState = function(self, eyes, mouseX, mouseY, dt, fadeSpeed)
      local leftEye = eyes.left
      local rightEye = eyes.right

      -- 更新每只眼睛各自的触碰状态
      leftEye:updateTouchState(dt, leftEye:isPointOver(mouseX, mouseY), fadeSpeed)
      rightEye:updateTouchState(dt, rightEye:isPointOver(mouseX, mouseY), fadeSpeed)

      -- 返回整体触碰状态（任意一只被触碰即为 true）
      return leftEye.isTouching or rightEye.isTouching
    end
  }
end

---创建特效状态子管理器
---@return table 特效状态管理器
function StateManager:createEffectsManager()
  return {
    -- 更新瞳孔放大与反光效果
    ---@param eyes table 眼睛集合
    ---@param dt number 帧间隔时间
    ---@param mouseX number 鼠标 X 位置
    ---@param mouseY number 鼠标 Y 位置
    ---@param eyeSize number 眼睛尺寸
    ---@param reflectionConfig table 反光配置
    ---@param dilationConfig table 瞳孔放大配置
    ---@param fire table 火焰模块
    updateEffects = function(self, eyes, dt, mouseX, mouseY, eyeSize, reflectionConfig, dilationConfig, fire)
      local leftEye = eyes.left
      local rightEye = eyes.right

      -- 一次性计算全部特效
      local mousePosition = {x = mouseX, y = mouseY}
      local effects = self.parent.eyes.calculateEyeEffects(
        mousePosition,
        leftEye, rightEye,
        reflectionConfig, dilationConfig
      )

      -- 更新反光
      leftEye:updateReflection(
        effects.leftReflection, effects.leftX, effects.leftY,
        reflectionConfig.fadeSpeed, dt
      )

      rightEye:updateReflection(
        effects.rightReflection, effects.rightX, effects.rightY,
        reflectionConfig.fadeSpeed, dt
      )

      -- 更新瞳孔放大
      leftEye:updatePupilDilation(
        effects.leftDilation,
        dilationConfig.fadeSpeed,
        dt
      )

      rightEye:updatePupilDilation(
        effects.rightDilation,
        dilationConfig.fadeSpeed,
        dt
      )
    end,

    -- 计算并更新抖动效果
    ---@param isTouching boolean 是否有眼睛正被触碰
    ---@param shakeAmount number 最大抖动幅度
    ---@return number shakeX X 方向抖动值
    ---@return number shakeY Y 方向抖动值
    updateShake = function(self, isTouching, shakeAmount)
      if isTouching then
        return love.math.random(-shakeAmount, shakeAmount), love.math.random(-shakeAmount, shakeAmount)
      else
        return 0, 0
      end
    end
  }
end

---以集中方式更新所有状态
---@param dt number 帧间隔时间
function StateManager:update(dt)
  -- 更新鼠标位置（取整避免抖动）
  local x, y = love.mouse.getPosition()
  self.mousePosition.x = math.floor(x)
  self.mousePosition.y = math.floor(y)

  -- 更新漂浮动画的计时
  self.motion:updateTime(dt, self.eyes.floating)

  -- 更新眼睛的漂浮位置
  local mousePos = {x = self.mousePosition.x, y = self.mousePosition.y}
  self.eyes.eyes.left:updateFloating(dt, self.motion.timeX, self.motion.timeY, self.eyes.floating, mousePos)
  self.eyes.eyes.right:updateFloating(dt, self.motion.timeX, self.motion.timeY, self.eyes.floating, mousePos)

  -- 更新触碰交互
  self.touching = self.interaction:updateTouchState(
    self.eyes.eyes,
    self.mousePosition.x,
    self.mousePosition.y,
    dt,
    self.eyes.fadeSpeed
  )

  -- 在特效子管理器中保存对父管理器的引用
  self.effects.parent = self

  -- 更新视觉特效（反光、瞳孔放大）
  self.effects:updateEffects(
    self.eyes.eyes,
    dt,
    self.mousePosition.x,
    self.mousePosition.y,
    self.eyes.eyeSize,
    self.eyes.reflection,
    self.eyes.pupilDilation,
    self.eyes.fireModule  -- 目前已不用于计算
  )

  -- 更新抖动效果
  self.shake.x, self.shake.y = self.effects:updateShake(self.touching, self.eyes.shakeAmount)
end

return StateManager
