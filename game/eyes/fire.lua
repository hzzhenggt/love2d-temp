--[[
================================================================================
 eyes/fire.lua —— 火焰粒子特效模块
================================================================================
 作用：
   实现跟随鼠标光标的火焰特效，由四套粒子系统分层叠加而成：
     - fire（外焰）  ：外层不规则跳动的火苗
     - core（核心）  ：稳定的内核火焰
     - spark（火星） ：偶尔迸出的明亮火星（手动控制发射）
     - smoke（烟雾） ：上升的烟雾

 设计要点：
   - 使用 Fire 类（面向对象）封装一个火焰实例；粒子图片等资源在所有实例间
     共享，并用引用计数管理生命周期。
   - 各粒子系统的参数集中定义在 Fire.PARTICLE_CONFIGS 中，并与基础模板合并。
   - 文件末尾创建了一个全局实例，并通过元表把实例方法转发为模块级函数，
     以兼容旧的调用方式（fire.update / fire.draw 等）。
================================================================================
--]]

local overlayStats = require("lib.overlayStats")

---@class Fire 火焰特效与粒子系统类
local Fire = {}
Fire.__index = Fire

-- 火焰相关颜色（类级别的共享静态数据）
Fire.COLORS = {
  fire = {
    { 1, 0.7, 0, 0.8 },   -- 金橙色
    { 1, 0.4, 0, 0.7 },   -- 橙色
    { 1, 0.2, 0, 0.5 },   -- 红橙色
    { 0.7, 0.1, 0, 0.3 }, -- 暗红色
    { 0.4, 0, 0, 0 }      -- 淡出至透明
  },
  corefire = {
    { 1, 1, 0.8, 0.9 },   -- 亮黄色
    { 1, 0.8, 0.2, 0.7 }, -- 黄橙色
    { 1, 0.6, 0, 0.5 },   -- 橙色
    { 1, 0.3, 0, 0.3 },   -- 偏红的橙色
    { 0.8, 0.1, 0 }       -- 淡出
  },
  spark = {
    { 1, 1, 1, 1 },       -- 白色
    { 1, 1, 0.6, 0.8 },   -- 亮黄色
    { 1, 0.3, 0, 0.3 },   -- 偏红的橙色
    { 1, 0.6, 0.1, 0 }    -- 淡出至透明
  },
  smoke = {
    { 0.5, 0.5, 0.5, 0 },   -- 以透明开始
    { 0.4, 0.4, 0.4, 0.2 }, -- 浅灰，略带透明
    { 0.3, 0.3, 0.3, 0.1 }, -- 中灰，逐渐淡出
    { 0.2, 0.2, 0.2, 0 }    -- 深灰，完全透明
  },
  reflection = {
    { 1, 0.95, 0.8, 1.0 },  -- 明亮的白黄色
    { 1, 0.8, 0.3, 0.7 }    -- 逐渐淡出的橙黄色
  }
}

-- 作为类属性的基础配置模板
Fire.BASE_PARTICLE_CONFIG = {
  direction = -math.pi/2, -- 发射方向（向上）
  sizeVariation = 0.5,
  autostart = true
}

Fire.BASE_FIRE_CONFIG = {
  spread = math.pi/3,
  radial = { min = -10, max = 10 },
  tangential = { min = -20, max = 20 }
}

-- 各粒子系统的配置模板
Fire.PARTICLE_CONFIGS = {
  fire = {
    count = 100,
    lifetime = { min = 0.5, max = 1.2 },
    emissionRate = 70,
    sizeVariation = 0.6,
    acceleration = { minX = -15, minY = -80, maxX = 15, maxY = -100 },
    speed = { min = 15, max = 60 },
    sizes = { 0.2, 0.7, 0.5, 0.2 },
    spread = Fire.BASE_FIRE_CONFIG.spread,
    radial = Fire.BASE_FIRE_CONFIG.radial,
    tangential = Fire.BASE_FIRE_CONFIG.tangential,
    spin = { min = -0.5, max = 0.5 },
    spinVariation = 1,
    -- 其余项使用基础默认配置
  },

  core = {
    count = 50,
    lifetime = { min = 0.3, max = 0.8 },
    emissionRate = 50,
    sizeVariation = 0.3,
    acceleration = { minX = -5, minY = -100, maxX = 5, maxY = -130 },
    speed = { min = 20, max = 40 },
    sizes = { 0.4, 0.6, 0.3, 0.1 },
    spread = math.pi/8,
    radial = { min = -2, max = 2 },
    tangential = { min = -5, max = 5 },
    -- 其余项使用基础默认配置
  },

  spark = {
    count = 30,
    lifetime = { min = 0.5, max = 1.5 },
    emissionRate = 0, -- 手动控制发射
    acceleration = { minX = -20, minY = -200, maxX = 20, maxY = -300 },
    speed = { min = 50, max = 150 },
    sizes = { 0.6, 0.4, 0.2, 0 },
    spread = math.pi/2,
    radial = { min = -50, max = 50 },
    tangential = { min = -20, max = 20 },
    spin = { min = -2, max = 2 },
    spinVariation = 1,
    autostart = false,
    -- 其余项使用基础默认配置
  },

  smoke = {
    count = 40,
    lifetime = { min = 1.0, max = 2.5 },
    emissionRate = 15,
    sizeVariation = 0.8,
    acceleration = { minX = -5, minY = -20, maxX = 5, maxY = -40 },
    speed = { min = 5, max = 15 },
    sizes = { 0.1, 0.6, 1.0, 1.3 },
    spread = math.pi/2,
    radial = { min = -10, max = 10 },
    tangential = { min = -20, max = 20 },
    spin = { min = 0.1, max = 0.8 },
    spinVariation = 1,
    offset = function() return love.math.random(-5,5), love.math.random(60,90) end,
    -- 其余项使用基础默认配置
  }
}

-- 所有实例共享的资源
Fire.resources = {
  particleImage = nil,
  sparkImage = nil,
  initialized = false,
  refCount = 0
}

-- 按需初始化共享资源
function Fire.initResources()
  if Fire.resources.initialized then
    Fire.resources.refCount = Fire.resources.refCount + 1
    return
  end

  -- 创建火焰粒子图片（仅创建一次）
  Fire.resources.particleImage = Fire.createFlameImage()
  Fire.resources.sparkImage = Fire.createSparkImage()
  Fire.resources.initialized = true
  Fire.resources.refCount = 1
end

-- 当不再需要时释放共享资源
function Fire.releaseResources()
  Fire.resources.refCount = Fire.resources.refCount - 1
  if Fire.resources.refCount <= 0 then
    if Fire.resources.particleImage then
      Fire.resources.particleImage:release()
      Fire.resources.particleImage = nil
    end
    if Fire.resources.sparkImage then
      Fire.resources.sparkImage:release()
      Fire.resources.sparkImage = nil
    end
    Fire.resources.initialized = false
    Fire.resources.refCount = 0
  end
end

-- 将图片创建函数提升为类级别的静态方法
-- 创建火苗（水滴形）粒子图片
function Fire.createFlameImage()
  local particleImg = love.graphics.newCanvas(32, 32)
  love.graphics.setCanvas(particleImg)
  love.graphics.clear()

  -- 开启抗锯齿并绘制一个水滴/火苗形状
  local prevLineStyle = love.graphics.getLineStyle()
  love.graphics.setLineStyle("smooth")
  love.graphics.setColor(1, 1, 1)

  -- 创建水滴形状（上窄下宽）
  local points = {}
  local centerX, centerY = 16, 16
  for i = 0, 32 do
    local angle = (i / 32) * math.pi * 2
    -- 调整半径以形成水滴形状
    local radius = 14 * (1 - 0.3 * math.sin(angle)) -- 顶部略窄
    local x = centerX + radius * math.cos(angle)
    local y = centerY + radius * math.sin(angle) * 1.2 -- 纵向拉伸
    table.insert(points, x)
    table.insert(points, y)
  end
  love.graphics.polygon("fill", unpack(points))

  -- 添加光晕效果
  love.graphics.setColor(1, 1, 1, 0.5)
  love.graphics.circle("fill", 16, 16, 16)

  love.graphics.setLineStyle(prevLineStyle)
  love.graphics.setCanvas()

  return particleImg
end

-- 创建火星（圆点）粒子图片
function Fire.createSparkImage()
  local sparkImg = love.graphics.newCanvas(16, 16)
  love.graphics.setCanvas(sparkImg)
  love.graphics.clear()

  local prevLineStyle = love.graphics.getLineStyle()
  love.graphics.setLineStyle("smooth")
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.circle("fill", 8, 8, 6)
  love.graphics.setColor(1, 1, 0.8, 0.6)
  love.graphics.circle("fill", 8, 8, 8)
  love.graphics.setLineStyle(prevLineStyle)
  love.graphics.setCanvas()

  return sparkImg
end

---创建一个新的 Fire 实例
---@return Fire
function Fire.new()
  -- 初始化共享资源
  Fire.initResources()

  local self = setmetatable({}, Fire)

  -- 实例属性（原先的全局状态）
  self.fireSystem = nil    -- 外层不规则火焰
  self.coreSystem = nil    -- 稳定的内核
  self.sparkSystem = nil   -- 偶发的明亮火星
  self.smokeSystem = nil   -- 烟雾效果

  -- 控制火星发射的计时器
  self.sparkTimer = 0
  self.sparkInterval = 0.15

  -- 颜色引用（可按实例自定义）
  self.colors = Fire.COLORS

  -- 初始化粒子系统
  self:initParticleSystem()

  return self
end

-- 清理方法
function Fire:destroy()
  -- 释放各粒子系统
  if self.fireSystem then self.fireSystem:release() end
  if self.coreSystem then self.coreSystem:release() end
  if self.sparkSystem then self.sparkSystem:release() end
  if self.smokeSystem then self.smokeSystem:release() end

  -- 释放对共享资源的引用
  Fire.releaseResources()
end

---根据预定义配置类型创建一个粒子系统
---@param type string 粒子系统类型（'fire'、'core'、'spark'、'smoke'）
---@param image love.Canvas 粒子使用的图片
---@return love.ParticleSystem 配置完成的粒子系统
function Fire:createParticleSystem(type, image)
  -- 获取该类型的配置
  local config = Fire.PARTICLE_CONFIGS[type]
  if not config then
    error("Unknown particle system type: " .. tostring(type))
  end

  -- 以指定粒子数量创建系统
  local system = love.graphics.newParticleSystem(image, config.count)

  -- 在标准配置之前应用特殊配置
  if type == "smoke" and config.offset then
    local offsetX, offsetY = config.offset()
    system:setOffset(offsetX, offsetY)
  end

  -- 将类型配置与基础配置合并，得到完整配置
  local fullConfig = {
    -- 先应用基础默认值
    direction = Fire.BASE_PARTICLE_CONFIG.direction,
    sizeVariation = Fire.BASE_PARTICLE_CONFIG.sizeVariation,
    autostart = Fire.BASE_PARTICLE_CONFIG.autostart,

    -- 再应用类型专属配置
    lifetime = config.lifetime,
    emissionRate = config.emissionRate,
    sizeVariation = config.sizeVariation or Fire.BASE_PARTICLE_CONFIG.sizeVariation,
    acceleration = config.acceleration,
    speed = config.speed,
    sizes = config.sizes,
    spread = config.spread,
    radial = config.radial,
    tangential = config.tangential,
    colors = self.colors[type == "core" and "corefire" or type], -- 将 'core' 映射到 'corefire'
    spin = config.spin,
    spinVariation = config.spinVariation,
    autostart = config.autostart ~= nil and config.autostart or Fire.BASE_PARTICLE_CONFIG.autostart
  }

  -- 配置并返回该粒子系统
  return self:configureParticleSystem(system, fullConfig)
end

---用通用属性配置一个粒子系统
---@param particleSystem love.ParticleSystem 要配置的粒子系统
---@param config table 配置参数
function Fire:configureParticleSystem(particleSystem, config)
  particleSystem:setParticleLifetime(config.lifetime.min, config.lifetime.max)
  particleSystem:setEmissionRate(config.emissionRate)
  particleSystem:setSizeVariation(config.sizeVariation)
  particleSystem:setLinearAcceleration(config.acceleration.minX, config.acceleration.minY,
                                       config.acceleration.maxX, config.acceleration.maxY)
  particleSystem:setSpeed(config.speed.min, config.speed.max)
  particleSystem:setSizes(unpack(config.sizes))
  particleSystem:setDirection(config.direction)
  particleSystem:setSpread(config.spread)
  particleSystem:setRadialAcceleration(config.radial.min, config.radial.max)
  particleSystem:setTangentialAcceleration(config.tangential.min, config.tangential.max)
  particleSystem:setColors(unpack(config.colors))

  if config.spin then
    particleSystem:setSpin(config.spin.min, config.spin.max)
    particleSystem:setSpinVariation(config.spinVariation or 1)
  end

  if config.autostart then
    particleSystem:start()
  end

  return particleSystem
end

---创建并初始化光标火焰特效所需的各粒子系统
---@return love.ParticleSystem 外焰粒子系统
---@return love.ParticleSystem 核心火焰粒子系统
---@return love.ParticleSystem 火星粒子系统
---@return love.ParticleSystem 烟雾粒子系统
function Fire:initParticleSystem()
  -- 使用共享资源与统一的创建函数
  local fireSystem = self:createParticleSystem("fire", Fire.resources.particleImage)
  local coreSystem = self:createParticleSystem("core", Fire.resources.particleImage)
  local sparkSystem = self:createParticleSystem("spark", Fire.resources.sparkImage)
  local smokeSystem = self:createParticleSystem("smoke", Fire.resources.particleImage)

  -- 将各系统保存到实例属性
  self.fireSystem = fireSystem
  self.coreSystem = coreSystem
  self.sparkSystem = sparkSystem
  self.smokeSystem = smokeSystem

  return fireSystem, coreSystem, sparkSystem, smokeSystem
end

---将各粒子系统注册到性能统计浮层
---@param overlayStatsModule table 可选的统计浮层模块，用于注册粒子系统
function Fire:registerWithStats(overlayStatsModule)
  if not overlayStatsModule then return end

  local systems = {self.fireSystem, self.coreSystem, self.sparkSystem, self.smokeSystem}
  for _, system in ipairs(systems) do
    overlayStatsModule.registerParticleSystem(system)
  end
end

---更新单个粒子系统的位置
---@param system love.ParticleSystem 要更新的粒子系统
---@param dt number 帧间隔时间
---@param x number X 位置
---@param y number Y 位置
local function updateSystem(system, dt, x, y)
  system:update(dt)
  system:setPosition(x, y)
end

---更新火焰的各粒子系统
---@param dt number 帧间隔时间
---@param x number 火焰（鼠标）当前的 x 位置
---@param y number 火焰（鼠标）当前的 y 位置
function Fire:update(dt, x, y)
  -- 更新全部粒子系统
  updateSystem(self.fireSystem, dt, x, y)
  updateSystem(self.coreSystem, dt, x, y)
  updateSystem(self.smokeSystem, dt, x, y)
  updateSystem(self.sparkSystem, dt, x, y)

  -- 火星发射控制——随机迸发火星
  self.sparkTimer = self.sparkTimer + dt
  if self.sparkTimer >= self.sparkInterval then
    self.sparkTimer = 0
    self.sparkInterval = love.math.random(0.05, 0.3)
    self.sparkSystem:emit(love.math.random(1, 5))
  end
end

---绘制火焰特效
function Fire:draw()
  -- FIXME: 将颜色设为黄色，以防鼠标移动时火焰被"吹灭"（变暗）
  love.graphics.setColor({ 1, 1, 0 })

  -- 保存当前混合模式
  local prevBlendMode = love.graphics.getBlendMode()

  -- 按从后到前的顺序绘制各层
  love.graphics.setBlendMode("alpha")
  love.graphics.draw(self.smokeSystem)
  love.graphics.draw(self.coreSystem)

  love.graphics.setBlendMode("add")
  love.graphics.draw(self.fireSystem)
  love.graphics.draw(self.sparkSystem)

  -- 恢复之前的混合模式
  love.graphics.setBlendMode(prevBlendMode)
end

-- 为兼容旧代码而设 —— 用元表自动转发实例方法
local globalInstance = Fire.new()

local fire = setmetatable({
  -- 显式定义的属性
  Fire = Fire,
  colors = globalInstance.colors
}, {
  __index = function(_, key)
    local value = globalInstance[key]
    if type(value) == "function" then
      -- 自动包装实例方法，供模块级（全局）调用
      return function(...)
        return value(globalInstance, ...)
      end
    end
    return value
  end
})

-- load 是特例，因为它需要执行注册操作
fire.load = function() globalInstance:registerWithStats(overlayStats) end

return fire
