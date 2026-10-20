--[[
================================================================================
 eyes/eyes.lua —— 眼睛示例场景主模块
================================================================================
 作用：
   这是整个 "eyes"（眼睛）示例 demo 的核心模块，负责绘制并管理两只可交互的
   悬浮眼球。它把场景中的各子系统组装到一起：
     - background（视差背景）
     - audio（音频）
     - fire（跟随鼠标的火焰）
     - shadows（眼球阴影）
     - 工具模块：vector / color_utils / state_manager / resource_manager

 交互与特效概览：
     - 眼球随正弦波轻微漂浮，并会被"火焰"（鼠标光标）吸引。
     - 瞳孔以惯性平滑地跟随鼠标。
     - 鼠标越靠近眼睛，瞳孔越放大、反光越强。
     - 当鼠标触碰到眼睛时：眼球泛红、出现血丝、整体抖动，并播放音效。
     - 通过 HTTPS 检测站点是否在线，据此改变虹膜颜色（在线为绿色）。

 结构说明：
     1. Eye 类      —— 表示单只眼睛及其全部属性与行为。
     2. 绘制辅助函数 —— drawEyeBase / drawIris / drawPupil / drawReflection 等。
     3. eyes 公共模块—— 对外暴露 load / update / draw / unload 等接口。
================================================================================
--]]

local background = require("eyes.background")
local audio = require("eyes.audio")
local fire = require("eyes.fire")
local shadows = require("eyes.shadows")
local vector = require("eyes.utils.vector")
local colorUtils = require("eyes.utils.color_utils")
local StateManager = require("eyes.utils.state_manager")
local ResourceManager = require("eyes.utils.resource_manager")

---@class Eye 表示一只眼睛及其全部属性
---@field x number 眼睛的 X 坐标
---@field y number 眼睛的 Y 坐标
---@field size number 眼睛尺寸
---@field fade number 当前渐变状态（0-1）
---@field floatOffset table {x=number, y=number} 当前漂浮偏移
---@field velocity table {x=number, y=number} 当前吸引速度
---@field attractOffset table {x=number, y=number} 当前吸引偏移
---@field reflection table {intensity=number, x=number, y=number} 反光属性
---@field pupilDilation number 当前瞳孔放大值（0-1）
---@field isTouching boolean 眼睛当前是否正被触碰
---@field pupilTarget table {x=number, y=number} 瞳孔的目标位置
---@field pupilCurrent table {x=number, y=number} 瞳孔的当前位置
local Eye = {}
Eye.__index = Eye

---创建一个新的 Eye 实例
---@param id string 眼睛标识（如 "left"、"right"）
---@param x number 初始 X 位置
---@param y number 初始 Y 位置
---@param size number 眼睛尺寸
---@param phaseX number X 方向漂浮的初始相位
---@param phaseY number Y 方向漂浮的初始相位
---@return Eye
function Eye.new(id, x, y, size, phaseX, phaseY)
  local self = setmetatable({}, Eye)
  self.id = id
  self.x = x
  self.y = y
  self.baseX = x -- 保存基础位置
  self.baseY = y
  self.size = size
  self.fade = 0
  self.floatOffset = {x = 0, y = 0}
  self.velocity = {x = 0, y = 0}
  self.attractOffset = {x = 0, y = 0}
  self.phaseX = phaseX
  self.phaseY = phaseY
  self.reflection = {
    intensity = 0,
    x = 0,
    y = 0
  }
  self.pupilDilation = 0
  self.isTouching = false

  -- 初始化瞳孔跟踪属性
  self.pupilTarget = {x = x, y = y}
  self.pupilCurrent = {x = x, y = y}

  return self
end

---根据基础位置与漂浮偏移计算眼睛的实际位置
---@return number x 实际 X 位置
---@return number y 实际 Y 位置
function Eye:getPosition()
  return self.baseX + self.floatOffset.x,
         self.baseY + self.floatOffset.y
end

---设置眼睛的基础位置
---@param x number 基础 X 位置
---@param y number 基础 Y 位置
function Eye:setBasePosition(x, y)
  self.baseX = x
  self.baseY = y
end

---更新本眼睛的漂浮效果
---@param dt number 帧间隔时间
---@param timeX number 全局时间 X
---@param timeY number 全局时间 Y
---@param config table 漂浮配置
---@param attractionPoint table {x=number, y=number} 吸引点（如鼠标/火焰位置）
function Eye:updateFloating(dt, timeX, timeY, config, attractionPoint)
  -- 计算振荡分量（简谐运动）
  local floatX = math.sin(timeX + self.phaseX) * config.amplitudeX
  local floatY = math.sin(timeY + self.phaseY) * config.amplitudeY

  -- 更新吸引物理（基于速度向吸引点移动）
  self:updateAttractionPhysics(dt, attractionPoint, config)

  -- 将振荡与吸引偏移合并得到最终位置
  self.floatOffset.x = floatX + self.attractOffset.x
  self.floatOffset.y = floatY + self.attractOffset.y
end

---更新眼睛的吸引物理
---@param dt number 帧间隔时间
---@param attractionPoint table {x=number, y=number} 吸引点
---@param config table 含吸引参数的漂浮配置
function Eye:updateAttractionPhysics(dt, attractionPoint, config)
  -- 对当前速度施加阻尼（模拟拖拽/摩擦）
  self.velocity.x = self.velocity.x * config.dampingFactor
  self.velocity.y = self.velocity.y * config.dampingFactor

  -- 获取当前眼睛位置
  local eyeX, eyeY = self:getPosition()

  -- 计算指向吸引点的向量
  local dx = attractionPoint.x - eyeX
  local dy = attractionPoint.y - eyeY
  local distance = vector.length(dx, dy)

  -- 仅在吸引范围内才施加吸引力
  if distance < config.attractionRange then
    -- 计算吸引力（越近越强）
    local normalizedX, normalizedY = vector.normalize(dx, dy)
    local strengthFactor = 1.0 - (distance / config.attractionRange)
    local attractForce = strengthFactor * config.attractionStrength

    -- 将加速度施加到速度上
    local accelerationX = normalizedX * attractForce
    local accelerationY = normalizedY * attractForce

    self.velocity.x = self.velocity.x + accelerationX * dt
    self.velocity.y = self.velocity.y + accelerationY * dt

    -- 限制最大速度
    local maxVel = config.maxAttractionForce * dt
    self.velocity.x, self.velocity.y = vector.clamp(
      self.velocity.x, self.velocity.y, maxVel
    )
  end

  -- 根据速度更新位置
  self.attractOffset.x = self.attractOffset.x + self.velocity.x
  self.attractOffset.y = self.attractOffset.y + self.velocity.y
end

---判断某个点是否落在本眼睛范围内
---@param x number 点的 X 坐标
---@param y number 点的 Y 坐标
---@return boolean isOver 若点在眼睛上则为 true
function Eye:isPointOver(x, y)
  local eyeX, eyeY = self:getPosition()
  local distance = vector.distance(x, y, eyeX, eyeY)
  return distance < self.size
end

---更新触碰状态与渐变值
---@param dt number 帧间隔时间
---@param isTouched boolean 眼睛是否正被触碰
---@param fadeSpeed number 渐变变化速度
function Eye:updateTouchState(dt, isTouched, fadeSpeed)
  self.isTouching = isTouched

  if isTouched then
    self.fade = math.min(1, self.fade + dt * fadeSpeed)
  else
    self.fade = math.max(0, self.fade - dt * fadeSpeed)
  end
end

---更新反光属性
---@param targetIntensity number 目标反光强度
---@param x number 反光 X 位置
---@param y number 反光 Y 位置
---@param fadeSpeed number 反光渐变速度
---@param dt number 帧间隔时间
function Eye:updateReflection(targetIntensity, x, y, fadeSpeed, dt)
  self.reflection.intensity = self.reflection.intensity +
    (targetIntensity - self.reflection.intensity) * dt * fadeSpeed
  self.reflection.x = x
  self.reflection.y = y
end

---更新瞳孔放大
---@param targetDilation number 目标瞳孔放大值
---@param fadeSpeed number 放大变化速度
---@param dt number 帧间隔时间
function Eye:updatePupilDilation(targetDilation, fadeSpeed, dt)
  self.pupilDilation = self.pupilDilation +
    (targetDilation - self.pupilDilation) * dt * fadeSpeed
end

---带惯性地更新瞳孔的跟踪位置
---@param dt number 帧间隔时间
---@param targetX number 目标 X 位置
---@param targetY number 目标 Y 位置
---@param trackingSpeed number 瞳孔跟踪目标的速度
function Eye:updatePupilTracking(dt, targetX, targetY, trackingSpeed)
  -- 更新目标位置
  self.pupilTarget.x = targetX
  self.pupilTarget.y = targetY

  -- 带惯性地将当前位置向目标移动
  self.pupilCurrent.x = self.pupilCurrent.x +
    (self.pupilTarget.x - self.pupilCurrent.x) * dt * trackingSpeed
  self.pupilCurrent.y = self.pupilCurrent.y +
    (self.pupilTarget.y - self.pupilCurrent.y) * dt * trackingSpeed
end

-- 对外公开的模块
local eyes = {
  -- 基础配置
  eyeSize = 128,
  eyeSpacing = 320,
  shakeAmount = 5,
  fadeSpeed = 2, -- 颜色渐变过渡速度（单位/秒）

  -- 状态变量——将由 StateManager 管理
  x = 0,
  y = 0,

  -- 眼睛集合
  eyes = {},

  -- 漂浮效果配置
  floating = {
    -- 基础漂浮速度（弧度/秒）
    speedX = 0.9,
    speedY = 0.9,
    -- 偏离原点的最大漂浮距离
    amplitudeX = 15,
    amplitudeY = 10,
    -- 火焰吸引参数
    attractionStrength = 0.08,   -- 从 0.15 调低，使移动更平缓
    attractionRange = 400,       -- 吸引力起作用的最大距离
    maxAttractionForce = 0.4,    -- 每秒最大吸引力
    dampingFactor = 0.85,        -- 吸引速度的衰减快慢
  },

  -- 眼睛跟踪配置
  tracking = {
    speed = 15.0,                -- 眼睛跟踪的基础速度（越大跟踪越快）
    touchedSpeedFactor = 0.3,    -- 被触碰时跟踪速度乘以该系数（变慢）
    maxTrackingDistance = 0.5,   -- 瞳孔可偏离中心的最大距离（占眼睛尺寸的比例）
  },

  -- 火焰反光状态
  reflection = {
    fadeSpeed = 3,      -- 反光淡入/淡出的快慢
    maxIntensity = 0.9, -- 最大反光强度（为提升可见度而调高）
    minDistance = 80,   -- 出现反光的最小距离
    maxDistance = 350,  -- 反光强度降至最低时的距离
    baseSize = 0.07     -- 反光基础尺寸（占眼睛尺寸的比例，较小）
  },

  -- 瞳孔放大状态（随火焰靠近而变化）
  pupilDilation = {
    fadeSpeed = 2.5,       -- 放大过渡速度
    maxDilation = 0.30,    -- 额外的最大放大系数（放大 30%）
    minDistance = 100,     -- 达到最大放大的距离
    maxDistance = 400,     -- 开始出现放大的距离
  },

  -- 血丝纹理
  bloodVeinsTexture = nil,

  -- 眼睛纹理
  irisTexture = nil,
  pupilTexture = nil,

  -- 眼球着色器
  eyeShader = nil,

  -- 在线状态
  isOnline = false,

  -- 资源管理器
  resources = nil,
}

-- 眼睛状态
eyes.state = {
  touching = false,
}

-- 以下为局部定义的私有函数
---根据系数（0 到 1）在两个颜色之间插值
---@param color1 table 第一个颜色 {r, g, b}
---@param color2 table 第二个颜色 {r, g, b}
---@param factor number 插值系数（0 = color1，1 = color2）
---@return table 插值后的颜色 {r, g, b}
local function interpolateColor(color1, color2, factor)
  factor = math.max(0, math.min(1, factor)) -- 将系数限制在 0 到 1 之间
  return {
    color1[1] + (color2[1] - color1[1]) * factor,
    color1[2] + (color2[2] - color1[2]) * factor,
    color1[3] + (color2[3] - color1[3]) * factor
  }
end

---根据窗口尺寸计算两只眼睛的位置
---@param windowWidth number 窗口宽度
---@param windowHeight number 窗口高度
---@param eyeSpacing number 两眼间距
---@return number leftEyeX 左眼 x 坐标
---@return number rightEyeX 右眼 x 坐标
---@return number centerY 两眼共用的 y 坐标
local function calculateEyePositions(windowWidth, windowHeight, eyeSpacing)
  local centerY = windowHeight / 2
  local leftEyeX = (windowWidth / 2) - (eyeSpacing / 2)
  local rightEyeX = (windowWidth / 2) + (eyeSpacing / 2)
  return leftEyeX, rightEyeX, centerY
end

-- 绘制辅助函数
---使用着色器绘制眼球底色，实现渐变效果
---@param eyeX number 眼睛 X 位置
---@param eyeY number 眼睛 Y 位置
---@param eyeSize number 眼睛尺寸
---@param eyeColor table {r,g,b} 亮部颜色
---@param shadedEyeColor table {r,g,b} 暗部颜色
---@param dirX number 指向光源的 X 方向
---@param dirY number 指向光源的 Y 方向
local function drawEyeBase(eyeX, eyeY, eyeSize, eyeColor, shadedEyeColor, dirX, dirY)
  -- 计算高光位置的偏移（朝向火焰/光标）
  local highlightOffsetFactor = 0.4
  local highlightX = eyeX + (dirX * eyeSize * highlightOffsetFactor)
  local highlightY = eyeY + (dirY * eyeSize * highlightOffsetFactor)

  -- 将数值传入着色器
  eyes.eyeShader:send("eyeCenter", {eyeX, eyeY})
  eyes.eyeShader:send("highlightCenter", {highlightX, highlightY})
  eyes.eyeShader:send("eyeSize", eyeSize)
  eyes.eyeShader:send("brightColor", {eyeColor[1], eyeColor[2], eyeColor[3], 1.0})
  eyes.eyeShader:send("shadedColor", {shadedEyeColor[1], shadedEyeColor[2], shadedEyeColor[3], 1.0})

  -- 用着色器绘制眼球底色以实现渐变
  love.graphics.setShader(eyes.eyeShader)
  love.graphics.setColor(1.0, 1.0, 1.0, 1.0)
  love.graphics.circle("fill", eyeX, eyeY, eyeSize)
  love.graphics.setShader()
end

---当眼睛被触碰时在其上绘制血丝
---@param eyeX number 眼睛 X 位置
---@param eyeY number 眼睛 Y 位置
---@param eyeSize number 眼睛尺寸
---@param fadeValue number 血丝的渐变值（0-1）
local function drawBloodVeins(eyeX, eyeY, eyeSize, fadeValue)
  if not eyes.bloodVeinsTexture or fadeValue <= 0 then return end

  -- 保存当前混合模式
  local prevBlendMode = love.graphics.getBlendMode()
  love.graphics.setBlendMode("alpha")

  -- 计算缩放系数以匹配眼睛尺寸
  -- 原始纹理为 512x512，故缩放到眼睛直径（2 * eyeSize）
  local scale = (2 * eyeSize) / 512

  -- 以基于渐变值的透明度将纹理居中绘制在眼睛上
  love.graphics.setColor(1, 1, 1, fadeValue)
  love.graphics.draw(
    eyes.bloodVeinsTexture,
    eyeX, eyeY,
    0,                     -- 旋转（0 表示不旋转）
    scale, scale,          -- X、Y 方向缩放
    256, 256               -- 原点（512x512 纹理的中心）
  )

  -- 恢复之前的混合模式
  love.graphics.setBlendMode(prevBlendMode)
end

---计算虹膜与瞳孔的位置
---@param eyeX number 眼睛 X 位置
---@param eyeY number 眼睛 Y 位置
---@param eyeSize number 眼睛尺寸
---@param fadeValue number 用于振荡的渐变值（0-1）
---@param currentPupilX number 瞳孔当前 X 位置（用于惯性）
---@param currentPupilY number 瞳孔当前 Y 位置（用于惯性）
---@return number irisX 虹膜 X 位置
---@return number irisY 虹膜 Y 位置
---@return number pupilX 瞳孔 X 位置
---@return number pupilY 瞳孔 Y 位置
---@return number angle 方向角
local function calculatePupilPosition(eyeX, eyeY, eyeSize, fadeValue, currentPupilX, currentPupilY)
  local mouseX, mouseY = love.mouse.getPosition()
  local distanceX = mouseX - eyeX
  local distanceY = mouseY - eyeY

  -- 计算瞳孔可移动的最大距离
  local maxDistance = eyeSize * eyes.tracking.maxTrackingDistance

  -- 计算跟踪位置
  local distance = math.min(math.sqrt(distanceX^2 + distanceY^2), maxDistance)
  local angle = math.atan2(distanceY, distanceX)

  -- 使用眼睛跟踪系统给出的当前位置
  local trackingX = currentPupilX
  local trackingY = currentPupilY

  -- 计算振荡位置（眼睛被触碰时瞳孔抖动到的位置）
  local oscillationRange = eyeSize / 16
  local oscillationX = eyeX + love.math.random(-oscillationRange, oscillationRange)
  local oscillationY = eyeY + love.math.random(-oscillationRange, oscillationRange)

  -- 根据渐变值在跟踪位置与振荡位置之间插值
  local irisX = trackingX + (oscillationX - trackingX) * fadeValue
  local irisY = trackingY + (oscillationY - trackingY) * fadeValue

  -- 为瞳孔计算一个细微的额外偏移
  local pupilOffsetFactor = 0.10 -- 控制瞳孔相对虹膜额外移动的幅度
  local subtleDistance = distance * pupilOffsetFactor

  -- 将细微偏移应用到瞳孔位置
  local pupilX = irisX + (math.cos(angle) * subtleDistance)
  local pupilY = irisY + (math.sin(angle) * subtleDistance)

  return irisX, irisY, pupilX, pupilY, angle
end

---绘制虹膜纹理
---@param irisX number 虹膜 X 位置
---@param irisY number 虹膜 Y 位置
---@param eyeSize number 眼睛尺寸
---@param pupilColor table {r,g,b} 瞳孔颜色
local function drawIris(irisX, irisY, eyeSize, pupilColor)
  if not eyes.irisTexture then return end

  -- 计算虹膜纹理的缩放（约为眼睛尺寸的 140%）
  local irisScale = (eyeSize * 1.4) / 512

  -- 对虹膜进行颜色染色
  love.graphics.setColor(pupilColor)
  love.graphics.draw(
    eyes.irisTexture,
    irisX, irisY,
    0,                -- 不旋转
    irisScale, irisScale,
    256, 256         -- 512x512 纹理的中心
  )
end

---绘制带放大效果的瞳孔纹理
---@param pupilX number 瞳孔 X 位置
---@param pupilY number 瞳孔 Y 位置
---@param eyeSize number 眼睛尺寸
---@param dilationFactor number 放大系数（0-1）
local function drawPupil(pupilX, pupilY, eyeSize, dilationFactor)
  if not eyes.pupilTexture then return end

  -- 计算瞳孔基础缩放（含放大效果）
  local basePupilScale = eyeSize * 0.8 / 512
  -- 应用放大系数（最多放大 maxDilation 比例）
  local dilatedScale = basePupilScale * (1 + (eyes.pupilDilation.maxDilation * dilationFactor))

  -- 以原色绘制瞳孔
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(
    eyes.pupilTexture,
    pupilX, pupilY,
    0,                -- 不旋转
    dilatedScale, dilatedScale,
    256, 256         -- 512x512 纹理的中心
  )
end

---绘制火焰反光的亮点
---@param pupilX number 瞳孔 X 位置
---@param pupilY number 瞳孔 Y 位置
---@param eyeSize number 眼睛尺寸
---@param reflectionIntensity number 反光强度
---@param fadeValue number 眼睛的渐变值（会削弱反光）
local function drawReflection(pupilX, pupilY, eyeSize, reflectionIntensity, fadeValue)
  -- 计算实际反光强度——眼睛被触碰时反光完全淡出
  local actualIntensity = reflectionIntensity * (1.0 - fadeValue)

  if actualIntensity <= 0.01 then return end -- 仅在可见时绘制

  -- 保存当前混合模式与线条样式
  local prevBlendMode = love.graphics.getBlendMode()
  local prevLineStyle = love.graphics.getLineStyle()
  local prevLineWidth = love.graphics.getLineWidth()

  -- 启用平滑线条绘制
  love.graphics.setLineStyle("smooth")
  love.graphics.setLineWidth(2)

  -- 计算从瞳孔指向光标（火焰源）的角度
  local fireAngle = math.atan2(love.mouse.getY() - pupilY, love.mouse.getX() - pupilX)

  -- 计算相反的角度（瞳孔背离火焰的那一侧边缘）
  local glintAngle = fireAngle + math.pi

  -- 计算瞳孔半径，并把亮点定位在其边缘
  local pupilRadius = eyeSize * 0.15 -- 瞳孔半径的近似值
  local glintX = pupilX + math.cos(glintAngle) * pupilRadius
  local glintY = pupilY + math.sin(glintAngle) * pupilRadius

  -- 计算亮点尺寸——比之前明显更小
  local baseGlintSize = eyeSize * eyes.reflection.baseSize
  local glintSize = baseGlintSize * actualIntensity

  -- 使用加法混合实现发光效果
  love.graphics.setBlendMode("add")

  -- 从调色板获取反光颜色
  local mainGlintColor = colorUtils.getColor("reflections", "main")
  local coreGlintColor = colorUtils.getColor("reflections", "core")

  -- 绘制主亮点（带抗锯齿）
  love.graphics.setColor(
    mainGlintColor[1], mainGlintColor[2], mainGlintColor[3],
    0.8 * actualIntensity
  )
  love.graphics.circle("fill", glintX, glintY, glintSize)

  -- 叠加一个更亮的核心（带抗锯齿）
  love.graphics.setColor(
    coreGlintColor[1], coreGlintColor[2], coreGlintColor[3],
    0.9 * actualIntensity
  )
  love.graphics.circle("fill", glintX, glintY, glintSize * 0.6)

  -- 恢复之前的绘图设置
  love.graphics.setBlendMode(prevBlendMode)
  love.graphics.setLineStyle(prevLineStyle)
  love.graphics.setLineWidth(prevLineWidth)
end

---绘制单只眼睛
---@param eye Eye 要绘制的眼睛
---@param isOnline boolean 系统是否在线
local function drawEye(eye, isOnline)
  local eyeX, eyeY = eye:getPosition()
  local eyeSize = eye.size
  local fadeValue = eye.fade
  local reflectionIntensity = eye.reflection.intensity
  local dilationFactor = eye.pupilDilation

  -- 从颜色工具获取基础颜色
  local whiteColor = colorUtils.getMainColor("white")
  local shadedWhiteColor = colorUtils.getMainColor("shadedWhite")
  local lightPinkColor = colorUtils.getMainColor("lightPink")
  local baseIrisColor

  -- 根据在线状态选择虹膜颜色
  if isOnline then
    baseIrisColor = colorUtils.getColor("eyes", "online.iris")
  else
    baseIrisColor = colorUtils.getColor("eyes", "normal.iris")
  end

  local touchedIrisColor = colorUtils.getColor("eyes", "touched.iris")

  -- 根据渐变值在白色与粉色之间插值
  local eyeColor = colorUtils.lerp(whiteColor, lightPinkColor, fadeValue)
  local shadedEyeColor = colorUtils.lerp(shadedWhiteColor, lightPinkColor, fadeValue)

  -- 根据触碰状态插值虹膜颜色
  local pupilColor = colorUtils.lerp(baseIrisColor, touchedIrisColor, fadeValue)

  -- 计算从眼睛指向火焰/光标的方向向量
  local fireX, fireY = love.mouse.getPosition()
  local dirX, dirY = vector.normalize(fireX - eyeX, fireY - eyeY)

  -- 若归一化失败（罕见情况：光标正好在眼睛中心）
  if dirX == 0 and dirY == 0 then
    dirX, dirY = 0, -1
  end

  -- 按从后到前的顺序绘制眼睛各组成部分
  drawEyeBase(eyeX, eyeY, eyeSize, eyeColor, shadedEyeColor, dirX, dirY)
  drawBloodVeins(eyeX, eyeY, eyeSize, fadeValue)

  -- 使用当前跟踪位置计算虹膜与瞳孔的位置
  local irisX, irisY, pupilX, pupilY = calculatePupilPosition(
    eyeX, eyeY, eyeSize, fadeValue,
    eye.pupilCurrent.x, eye.pupilCurrent.y
  )

  drawIris(irisX, irisY, eyeSize, pupilColor)
  drawPupil(pupilX, pupilY, eyeSize, dilationFactor)
  drawReflection(pupilX, pupilY, eyeSize, reflectionIntensity, fadeValue)
end

---更新并绘制火焰特效与火焰点
---@param x number 鼠标 X 位置
---@param y number 鼠标 Y 位置
local function drawFireEffect(x, y)
  -- 使用火焰模块绘制火焰特效
  fire.draw()

  -- 隐藏鼠标指针
  love.mouse.setVisible(false)
end

---计算某个点到一只眼睛的距离
---@param pointX number 点的 X 位置
---@param pointY number 点的 Y 位置
---@param eyeX number 眼睛 X 位置
---@param eyeY number 眼睛 Y 位置
---@return number distance 点到眼睛的距离
function eyes.calculateDistanceToEye(pointX, pointY, eyeX, eyeY)
  return math.sqrt((pointX - eyeX)^2 + (pointY - eyeY)^2)
end

---根据距离与配置计算强度值
---@param distance number 到眼睛的距离
---@param config table 含 minDistance、maxDistance（及可选 maxIntensity）的配置
---@param minIntensity number 处于范围内时使用的最小强度（默认为 0）
---@param invert boolean 若为 true，则距离越近强度越低（默认为 false）
---@return number intensity 计算出的强度值（0-1 或 0-maxIntensity）
function eyes.calculateIntensityFromDistance(distance, config, minIntensity, invert)
  -- 默认值
  minIntensity = minIntensity or 0
  local maxIntensity = config.maxIntensity or 1

  -- 若超出范围则强度为 0
  if distance >= config.maxDistance then
    return 0
  end

  -- 计算归一化的距离系数（0-1）
  local distanceFactor = (distance - config.minDistance) / (config.maxDistance - config.minDistance)

  -- 限制到 0-1 范围
  distanceFactor = math.max(0, math.min(1, distanceFactor))

  -- 必要时反转（用于放大效果：越近效果越强）
  if invert then
    distanceFactor = 1 - distanceFactor
  else
    -- 常规情况（反光）：越近强度越高
    distanceFactor = 1 - distanceFactor
  end

  -- 计算最终强度并限制到范围内
  local intensity = distanceFactor * maxIntensity
  return math.max(minIntensity, math.min(maxIntensity, intensity))
end

---在一次遍历中计算两只眼睛的效果（反光与瞳孔放大）
---@param mousePosition table {x=number, y=number} 鼠标/光标位置
---@param leftEye Eye 左眼对象
---@param rightEye Eye 右眼对象
---@param reflectionConfig table 反光效果配置
---@param dilationConfig table 瞳孔放大效果配置
---@return table Effects 计算出的效果 {leftReflection=number, rightReflection=number, leftDilation=number, rightDilation=number}
function eyes.calculateEyeEffects(mousePosition, leftEye, rightEye, reflectionConfig, dilationConfig)
  -- 获取两只眼睛的位置
  local leftEyeX, leftEyeY = leftEye:getPosition()
  local rightEyeX, rightEyeY = rightEye:getPosition()

  -- 只计算一次到两只眼睛的距离
  local distanceToLeft = eyes.calculateDistanceToEye(mousePosition.x, mousePosition.y, leftEyeX, leftEyeY)
  local distanceToRight = eyes.calculateDistanceToEye(mousePosition.x, mousePosition.y, rightEyeX, rightEyeY)

  -- 计算反光强度
  local leftReflection = eyes.calculateIntensityFromDistance(distanceToLeft, reflectionConfig, 0.2)
  local rightReflection = eyes.calculateIntensityFromDistance(distanceToRight, reflectionConfig, 0.2)

  -- 计算瞳孔放大系数（反转距离关系）
  local leftDilation = eyes.calculateIntensityFromDistance(distanceToLeft, dilationConfig, 0, true)
  local rightDilation = eyes.calculateIntensityFromDistance(distanceToRight, dilationConfig, 0, true)

  -- 将所有计算结果一次性返回
  return {
    leftReflection = leftReflection,
    rightReflection = rightReflection,
    leftDilation = leftDilation,
    rightDilation = rightDilation,
    leftX = leftEyeX,
    leftY = leftEyeY,
    rightX = rightEyeX,
    rightY = rightEyeY
  }
end

---通过网络请求更新在线状态
---@return boolean isOnline 若站点在线则为 true
local function checkOnlineStatus()
  if not https then return false end

  local success, result = pcall(function()
    local code, body, headers = https.request("https://oval-tutu.com")
    return { code = code, body = body, headers = headers }
  end)

  return success and result and result.code and result.code < 400
end

---当鼠标位于眼睛上方时更新抖动效果
---@param shakeAmount number 最大抖动幅度
---@return number shakeX 结果 X 抖动值
---@return number shakeY 结果 Y 抖动值
local function updateShakeEffect(shakeAmount)
  if eyes.state.touching then
    return love.math.random(-shakeAmount, shakeAmount), love.math.random(-shakeAmount, shakeAmount)
  else
    return 0, 0
  end
end

---加载资源并初始化眼睛
function eyes.load()
  -- 初始化资源管理器并加载全部资源
  eyes.resources = ResourceManager.new():loadAll()

  -- 为常用资源保存引用，便于取用
  eyes.bloodVeinsTexture = eyes.resources:getTexture("bloodVeins")
  eyes.irisTexture = eyes.resources:getTexture("iris")
  eyes.pupilTexture = eyes.resources:getTexture("pupil")
  eyes.eyeShader = eyes.resources:getShader("eye")

  -- 设置默认字体
  eyes.resources:setDefaultFont("default")

  -- 加载其他模块
  background:load()
  audio:load()
  fire:load()
  shadows.load()

  -- 为状态管理器保存对火焰模块的引用
  eyes.fireModule = fire

  -- 检测在线状态
  eyes.isOnline = checkOnlineStatus()

  -- 创建眼睛实例
  local windowWidth, windowHeight = love.graphics.getDimensions()
  local leftX, rightX, centerY = calculateEyePositions(windowWidth, windowHeight, eyes.eyeSpacing)

  -- 以各自合适的相位创建两只眼睛
  eyes.eyes.left = Eye.new("left", leftX, centerY, eyes.eyeSize,
                          eyes.floating.phaseLeftX or 0,
                          eyes.floating.phaseLeftY or math.pi * 0.5)

  eyes.eyes.right = Eye.new("right", rightX, centerY, eyes.eyeSize,
                           eyes.floating.phaseRightX or math.pi * 0.7,
                           eyes.floating.phaseRightY or math.pi * 0.3)

  -- 初始化状态管理器
  eyes.stateManager = StateManager.new(eyes)

  -- 隐藏鼠标指针
  love.mouse.setVisible(false)
end

function eyes.update(dt)
  background:update(dt)

  local windowWidth = love.graphics.getWidth()
  local windowHeight = love.graphics.getHeight()

  -- 更新阴影位置
  shadows.update(dt, windowHeight)

  -- 每帧计算一次眼睛基础位置
  local leftEyeX, rightEyeX, centerY = calculateEyePositions(windowWidth, windowHeight, eyes.eyeSpacing)

  -- 更新两只眼睛对象的基础位置
  eyes.eyes.left:setBasePosition(leftEyeX, centerY)
  eyes.eyes.right:setBasePosition(rightEyeX, centerY)

  -- 通过集中式状态管理器更新所有状态
  eyes.stateManager:update(dt)

  -- 复制重要状态值，便于使用/向后兼容
  eyes.x = eyes.stateManager.mousePosition.x
  eyes.y = eyes.stateManager.mousePosition.y
  eyes.shakeX = eyes.stateManager.shake.x
  eyes.shakeY = eyes.stateManager.shake.y

  -- 带惯性地更新眼睛瞳孔跟踪
  local leftEye = eyes.eyes.left
  local rightEye = eyes.eyes.right
  local leftEyeX, leftEyeY = leftEye:getPosition()
  local rightEyeX, rightEyeY = rightEye:getPosition()

  -- 为两只眼睛计算目标位置
  local function calculateTargetPosition(eyeX, eyeY, eyeSize)
    local mouseX, mouseY = love.mouse.getPosition()
    local distanceX = mouseX - eyeX
    local distanceY = mouseY - eyeY

    -- 限制瞳孔偏离中心的最大距离
    local maxDistance = eyeSize * eyes.tracking.maxTrackingDistance
    local distance = math.sqrt(distanceX^2 + distanceY^2)

    if distance > maxDistance then
      local factor = maxDistance / distance
      distanceX = distanceX * factor
      distanceY = distanceY * factor
    end

    return eyeX + distanceX, eyeY + distanceY
  end

  -- 根据触碰状态计算跟踪速度
  local leftTrackingSpeed = eyes.tracking.speed
  local rightTrackingSpeed = eyes.tracking.speed

  if leftEye.isTouching then
    leftTrackingSpeed = leftTrackingSpeed * eyes.tracking.touchedSpeedFactor
  end

  if rightEye.isTouching then
    rightTrackingSpeed = rightTrackingSpeed * eyes.tracking.touchedSpeedFactor
  end

  -- 获取目标位置并更新瞳孔跟踪
  local leftTargetX, leftTargetY = calculateTargetPosition(leftEyeX, leftEyeY, leftEye.size)
  local rightTargetX, rightTargetY = calculateTargetPosition(rightEyeX, rightEyeY, rightEye.size)

  leftEye:updatePupilTracking(dt, leftTargetX, leftTargetY, leftTrackingSpeed)
  rightEye:updatePupilTracking(dt, rightTargetX, rightTargetY, rightTrackingSpeed)

  -- 用当前状态与光标位置更新音频系统
  audio:update(dt, {
    touching = eyes.stateManager.touching,
    touchingLeft = eyes.eyes.left.isTouching,
    touchingRight = eyes.eyes.right.isTouching
  }, eyes.x, eyes.y)

  -- 用当前鼠标位置更新火焰模块
  fire.update(dt, eyes.x, eyes.y)
end

function eyes.draw()
  local windowWidth = love.graphics.getWidth()
  local windowHeight = love.graphics.getHeight()

  -- 先绘制纯黑背景
  love.graphics.setColor(0, 0, 0)
  love.graphics.rectangle("fill", 0, 0, windowWidth, windowHeight)

  -- 从状态管理器获取抖动效果值
  local shakeX = eyes.stateManager.shake.x
  local shakeY = eyes.stateManager.shake.y

  love.graphics.push()
  love.graphics.translate(shakeX, shakeY)
  background:draw()

  -- 获取用于绘制阴影的实际眼睛位置
  local leftX, leftY = eyes.eyes.left:getPosition()
  local rightX, rightY = eyes.eyes.right:getPosition()

  -- 先绘制阴影，使其位于眼睛下方
  shadows.draw(leftX, leftY, eyes.eyeSize)
  shadows.draw(rightX, rightY, eyes.eyeSize)

  -- 绘制两只眼睛（含各自的渐变值、反光效果、瞳孔放大与在线状态）
  drawEye(eyes.eyes.left, eyes.isOnline)
  drawEye(eyes.eyes.right, eyes.isOnline)

  -- 仅绘制火焰特效
  drawFireEffect(eyes.x, eyes.y)

  love.graphics.pop()
end

-- 场景退出时清理音频
function eyes.unload()
  audio:stop()
end

return eyes
