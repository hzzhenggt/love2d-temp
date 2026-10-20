--[[
================================================================================
 lib/overlayStats.lua —— 性能统计浮层模块
================================================================================
 说明：
   本文件原为第三方库，现应项目需要进行了注释汉化。
   ⚠ 注意：若日后从上游更新此库，这里的中文注释会被覆盖/产生冲突。

 作用：
   在游戏画面左上角绘制一个半透明的性能监控浮层，实时显示 FPS、帧耗时、
   内存/显存占用、Draw Call、着色器切换、粒子数量以及渲染器/系统信息等。
   可用于开发期排查性能问题。

 开关方式：
     键盘：F3 显示/隐藏浮层，F5 开关垂直同步（VSync）
     手柄：Back + A 切换浮层，Back + B 切换 VSync
     触摸：双击右上角切换浮层；浮层开启时双击浮层区域切换 VSync

 工作原理：
   - update() 每帧采样各项指标，循环写入固定大小的样本缓冲（sampleSize）。
   - draw()   取样本的平均值并绘制到屏幕。
   - 粒子系统需先通过 registerParticleSystem 注册，才会被纳入统计。

 使用约定：
   在 main.lua 中，load/draw/update 以及键盘、触摸回调都应"最后调用"本模块，
   以保证统计到的是当帧的完整数据。
================================================================================
--]]

---@class overlayStats
---LÖVE 游戏的性能监控浮层模块
---@field isActive boolean 浮层当前是否可见
---@field sampleSize number 各指标保留的最大样本数
---@field vsyncEnabled boolean 当前的垂直同步状态
local name, version, vendor, device = love.graphics.getRendererInfo()
local overlayStats = {
  isActive = false,
  sampleSize = 60,
  vsyncEnabled = nil,
  lastControllerCheck = 0,
  CONTROLLER_COOLDOWN = 0.2,
  -- 存放已注册的活动粒子系统
  particleSystems = {},
  renderInfo = {
    name = name,
    version = version,
    vendor = vendor,
    device = device,
  },
  sysInfo = {
    arch = love.system.getOS() ~= "Web" and require("ffi").arch or "Web",
    os = love.system.getOS(),
    cpuCount = love.system.getProcessorCount(),
  },
  supportedFeatures = {
    glsl3 = false,
    pixelShaderHighp = false,
  },
  metrics = {
    canvases = {},
    canvasSwitches = {},
    drawCalls = {},
    drawCallsBatched = {},
    frameTime = {},
    imageCount = {},
    memoryUsage = {},
    shaderSwitches = {},
    textureMemory = {},
    particleCount = {},
  },
  currentSample = 0,
  -- 触摸激活相关参数
  touch = {
    cornerSize = 80, -- 激活区域的大小（像素）
    lastTapTime = 0, -- 上次点按的时间
    doubleTapThreshold = 0.5, -- 判定为双击的两次点按最大间隔
    overlayArea = {x = 10, y = 10, width = 280, height = 340}, -- 将在 draw 中更新
  },
}

-- 私有函数

---计算所有性能指标的平均值
---@return table averages 各指标平均值组成的表
local function getAverages()
  if not overlayStats.isActive then
    return {}
  end

  local averages = {}
  for metric, samples in pairs(overlayStats.metrics) do
    local sum = 0
    local count = 0
    for _, value in ipairs(samples) do
      sum = sum + value
      count = count + 1
    end
    averages[metric] = count > 0 and sum / count or 0
  end
  return averages
end

---检测并处理用于切换浮层的手柄输入
---由 update() 函数调用
local function handleController()
  -- 带冷却时间的手柄输入处理
  local currentTime = love.timer.getTime()
  if currentTime - overlayStats.lastControllerCheck < overlayStats.CONTROLLER_COOLDOWN then
    return
  end

  local joysticks = love.joystick.getJoysticks()
  for _, joystick in ipairs(joysticks) do
    if joystick:isGamepadDown("back") then
      if joystick:isGamepadDown("a") then
        toggleOverlay()
        overlayStats.lastControllerCheck = currentTime
      elseif joystick:isGamepadDown("b") then
        toggleVSync()
        overlayStats.lastControllerCheck = currentTime
      end
    end
  end
end

---切换浮层的显示/隐藏
---激活时会重置所有指标
local function toggleOverlay()
  overlayStats.isActive = not overlayStats.isActive
  -- 切换时重置各项指标
  for k, _ in pairs(overlayStats.metrics) do
    overlayStats.metrics[k] = {}
  end
  overlayStats.currentSample = 0
  print(string.format("Overlay %s", overlayStats.isActive and "enabled" or "disabled"))
end

---切换 LÖVE 的垂直同步（VSync）状态
---仅在浮层处于激活状态时生效
local function toggleVSync()
  if not overlayStats.isActive then
    return
  end
  overlayStats.vsyncEnabled = not overlayStats.vsyncEnabled
  love.window.setVSync(overlayStats.vsyncEnabled and 1 or 0)
  print(string.format("VSync %s", overlayStats.vsyncEnabled and "enabled" or "disabled"))
end

---检测给定的触摸位置是否落在右上角的激活区域内
---@param x number 触摸点的 x 坐标
---@param y number 触摸点的 y 坐标
---@return boolean inCorner 若触摸位于激活区域内则为 true
local function isTouchInCorner(x, y)
  local w, h = love.graphics.getDimensions()
  return x >= w - overlayStats.touch.cornerSize and y <= overlayStats.touch.cornerSize
end

---检测给定的触摸位置是否落在浮层区域内
---@param x number 触摸点的 x 坐标
---@param y number 触摸点的 y 坐标
---@return boolean insideOverlay 若触摸位于浮层区域内则为 true
local function isTouchInsideOverlay(x, y)
  local area = overlayStats.touch.overlayArea
  return x >= area.x and x <= area.x + area.width and
         y >= area.y and y <= area.y + area.height
end

---处理用于切换浮层的触摸输入
---@param x number 触摸点的 x 坐标
---@param y number 触摸点的 y 坐标
---@return nil
local function handleTouch(x, y)
  local currentTime = love.timer.getTime()
  local timeSinceLastTap = currentTime - overlayStats.touch.lastTapTime

  if overlayStats.isActive and isTouchInsideOverlay(x, y) then
    -- 处理落在已激活浮层内部的触摸
    if timeSinceLastTap <= overlayStats.touch.doubleTapThreshold then
      -- 在浮层内双击——切换 VSync
      toggleVSync()
      overlayStats.touch.lastTapTime = 0
    else
      overlayStats.touch.lastTapTime = currentTime
    end
  elseif isTouchInCorner(x, y) then
    -- 原始行为：点按右上角切换浮层
    if timeSinceLastTap <= overlayStats.touch.doubleTapThreshold then
      toggleOverlay()
      overlayStats.touch.lastTapTime = 0
    else
      overlayStats.touch.lastTapTime = currentTime
    end
  end
end

-- 公共 API

---初始化性能统计浮层模块
---@return nil
function overlayStats.load()
  -- 初始化滑动平均样本缓冲
  for k, _ in pairs(overlayStats.metrics) do
    overlayStats.metrics[k] = {}
  end
  -- 从 LÖVE 配置读取初始 VSync 状态
  overlayStats.vsyncEnabled = love.window.getVSync() == 1

  -- 获取图形特性支持信息
  local supported = love.graphics.getSupported()
  overlayStats.supportedFeatures.glsl3 = supported.glsl3
  overlayStats.supportedFeatures.pixelShaderHighp = supported.pixelshaderhighp
end

---当浮层激活时绘制性能浮层
---@return nil
function overlayStats.draw()
  if not overlayStats.isActive then
    return
  end

  local averages = getAverages()

  -- 准备浮层绘制
  love.graphics.push("all")
  local font = love.graphics.setNewFont(16)

  -- 根据渲染器版本等内容动态计算宽度
  local padding = 20    -- 左右各留 10px 内边距
  local baseWidth = 280 -- 最小宽度

  -- 计算渲染器版本文本所需宽度
  local versionTextWidth = font:getWidth(string.format("%s", overlayStats.renderInfo.version))
  local rendererInfoWidth = font:getWidth(
    string.format("Renderer: %s (%s)", overlayStats.renderInfo.name, overlayStats.renderInfo.vendor)
  )
  local systemInfoWidth = font:getWidth(
    overlayStats.sysInfo.os .. " " .. overlayStats.sysInfo.arch .. ": " .. overlayStats.sysInfo.cpuCount .. "x CPU"
  )

  -- 根据最宽的内容计算矩形宽度
  local contentWidth = math.max(versionTextWidth, rendererInfoWidth, systemInfoWidth, baseWidth)
  local rectangleWidth = contentWidth + padding

  -- 更新浮层区域尺寸，供触摸检测使用
  overlayStats.touch.overlayArea = {
    x = 10,
    y = 10,
    width = rectangleWidth,
    height = 340
  }

  -- 以动态宽度绘制背景矩形
  love.graphics.setColor(0, 0, 0, 0.8)
  love.graphics.rectangle("fill", 10, 10, rectangleWidth, 340)
  love.graphics.setColor(0.678, 0.847, 0.902, 1)

  -- 系统信息
  local y = 20
  love.graphics.print(
    overlayStats.sysInfo.os .. " " .. overlayStats.sysInfo.arch .. ": " .. overlayStats.sysInfo.cpuCount .. "x CPU",
    20,
    y
  )
  y = y + 30

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print(
    string.format("Renderer: %s (%s)", overlayStats.renderInfo.name, overlayStats.renderInfo.vendor),
    20,
    y
  )
  y = y + 20

  love.graphics.print(string.format("%s", overlayStats.renderInfo.version), 20, y)
  y = y + 30

  -- 安全处理帧耗时（对 nil/零做检查）
  love.graphics.setColor(0, 1, 0, 1)
  local frameTime = averages.frameTime or 0
  local fps = frameTime > 0 and (1 / frameTime) or 0
  love.graphics.print(string.format("FPS: %.1f (%.1fms)", fps, frameTime * 1000), 20, y)
  y = y + 20

  -- 每帧刷新 Canvas 数量
  local currentCanvases = love.graphics.getStats().canvases
  love.graphics.print(string.format("Canvases: %d", currentCanvases), 20, y)
  y = y + 20

  -- 每帧刷新 Canvas 切换次数
  local currentCanvasSwitches = love.graphics.getStats().canvasswitches
  love.graphics.print(string.format("Canvas Switches: %d", currentCanvasSwitches), 20, y)
  y = y + 20

  -- 每帧刷新着色器切换次数
  local currentShaderSwitches = love.graphics.getStats().shaderswitches
  love.graphics.print(string.format("Shader Switches: %d", currentShaderSwitches), 20, y)
  y = y + 20

  -- 每帧刷新 Draw Call 数量
  local currentDrawCalls = love.graphics.getStats().drawcalls
  local currentDrawCallsBatched = love.graphics.getStats().drawcallsbatched
  love.graphics.print(string.format("Draw Calls: %d (%d batched)", currentDrawCalls, currentDrawCallsBatched), 20, y)
  y = y + 20

  love.graphics.print(string.format("RAM: %.1f MB", averages.memoryUsage / 1024), 20, y)
  y = y + 20

  -- 每帧刷新纹理显存占用
  local currentTextureMemory = love.graphics.getStats().texturememory / (1024 * 1024)
  love.graphics.print(string.format("VRAM: %.1f MB", currentTextureMemory), 20, y)
  y = y + 20

  -- 每帧刷新图像数量
  local currentImages = love.graphics.getStats().images
  love.graphics.print(string.format("Images: %d", currentImages), 20, y)
  y = y + 20

  -- 显示粒子数量
  local currentParticleCount = averages.particleCount or 0
  love.graphics.print(string.format("Particles: %d", math.floor(currentParticleCount)), 20, y)
  y = y + 20

  -- 添加 GLSL 3 支持指示（支持为绿色，不支持为红色）
  love.graphics.setColor(overlayStats.supportedFeatures.glsl3 and { 0, 1, 0, 1 } or { 1, 0, 0, 1 })
  love.graphics.print(string.format("GLSL 3: %s", overlayStats.supportedFeatures.glsl3 and "Yes" or "No"), 20, y)
  y = y + 20

  -- 添加像素着色器 highp 支持指示
  love.graphics.setColor(overlayStats.supportedFeatures.pixelShaderHighp and { 0, 1, 0, 1 } or { 1, 0, 0, 1 })
  love.graphics.print(string.format("Pixel Shader highp: %s", overlayStats.supportedFeatures.pixelShaderHighp and "Yes" or "No"), 20, y)
  y = y + 20

  -- 添加 VSync 状态（用颜色区分开/关）
  love.graphics.setColor(overlayStats.vsyncEnabled and { 0, 1, 0, 1 } or { 1, 0, 0, 1 })
  love.graphics.print(string.format("VSync: %s", overlayStats.vsyncEnabled and "ON" or "OFF"), 20, y)

  love.graphics.pop()
end

---更新性能指标并处理手柄输入
---@param dt number 距上一帧的时间
---@return nil
function overlayStats.update(dt)
  handleController()

  if not overlayStats.isActive then
    return
  end
  overlayStats.currentSample = overlayStats.currentSample + 1
  if overlayStats.currentSample > overlayStats.sampleSize then
    overlayStats.currentSample = 1
  end

  -- 在任何绘制发生之前获取 Draw Call 统计
  local stats = love.graphics.getStats()
  overlayStats.metrics.canvases[overlayStats.currentSample] = stats.canvasses
  overlayStats.metrics.canvasSwitches[overlayStats.currentSample] = stats.canvasswitches
  overlayStats.metrics.drawCalls[overlayStats.currentSample] = stats.drawcalls
  overlayStats.metrics.drawCallsBatched[overlayStats.currentSample] = stats.drawcallsbatched
  overlayStats.metrics.imageCount[overlayStats.currentSample] = stats.images
  overlayStats.metrics.shaderSwitches[overlayStats.currentSample] = stats.shaderswitches
  overlayStats.metrics.textureMemory[overlayStats.currentSample] = stats.texturememory / (1024 * 1024)
  overlayStats.metrics.memoryUsage[overlayStats.currentSample] = collectgarbage("count")
  overlayStats.metrics.frameTime[overlayStats.currentSample] = dt

  -- 累加所有已注册粒子系统的粒子总数
  local totalParticles = 0
  for ps, _ in pairs(overlayStats.particleSystems) do
    if ps:isActive() then
      totalParticles = totalParticles + ps:getCount()
    end
  end
  overlayStats.metrics.particleCount[overlayStats.currentSample] = totalParticles
end

---处理浮层的键盘输入
---@param key string 被按下的按键
---@return nil
function overlayStats.handleKeyboard(key)
  if key == "f3" then
    toggleOverlay()
  elseif key == "f5" then
    toggleVSync()
  end
end

---处理用于切换浮层的触摸按下事件
---@param id any LÖVE 提供的触摸 ID
---@param x number 触摸点的 x 坐标
---@param y number 触摸点的 y 坐标
---@param dx number 触摸按下的水平分量
---@param dy number 触摸按下的垂直分量
---@param pressure number 触摸压力
---@return nil
function overlayStats.handleTouch(id, x, y, dx, dy, pressure)
  handleTouch(x, y)
end

---注册一个要被跟踪统计的粒子系统
---@param particleSystem love.ParticleSystem 要注册的粒子系统
---@return nil
function overlayStats.registerParticleSystem(particleSystem)
  overlayStats.particleSystems[particleSystem] = true
end

---从跟踪统计中注销一个粒子系统
---@param particleSystem love.ParticleSystem 要注销的粒子系统
---@return nil
function overlayStats.unregisterParticleSystem(particleSystem)
  overlayStats.particleSystems[particleSystem] = nil
end

return overlayStats
