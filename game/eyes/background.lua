--[[
================================================================================
 eyes/background.lua —— 视差滚动背景模块
================================================================================
 作用：
   绘制由 7 层图片组成的视差（parallax）背景，并实现水平无缝滚动。
   视差效果：越靠后的层滚动越慢，越靠前的层滚动越快，从而营造景深感。

 关键概念：
   - parallaxFactor（视差系数）：每层相对基础滚动速度的比例。
   - verticalOffset（垂直偏移）：个别层需要的上下位置微调。
   - scaleMode（缩放模式）："contain" 完整显示整张图，"cover" 填满屏幕。
   - 第 7 层（最远背景）做特殊处理：概念上视为双倍宽度，其右半部分用
     纯色矩形填充，以实现无限延伸的纯色远景。

 图片资源：eyes/bg/layer_01.png ~ layer_07.png，原始尺寸 2048x1546。
================================================================================
--]]

---@class ParallaxBackground 处理带水平滚动的视差背景层的模块
local background = {
  layers = {},           -- 存放所有层的数据
  width = 2048,          -- 图片原始宽度
  height = 1546,         -- 图片原始高度
  offset = 0,            -- 当前水平滚动位置
  scrollSpeed = 100,     -- 基础水平滚动速度（像素/秒）
  scaleMode = "contain", -- "contain" 完整显示整图，"cover" 填满屏幕
  maxScale = 1.0,        -- 最大缩放系数（1.0 = 原始尺寸的 100%）
}

-- 初始化：加载图片并设置各层
function background:load()
  -- 若已有层数据则先清空
  self.layers = {}

  -- 定义视差系数——最远层（第 7 层）移动最慢，最近层（第 1 层）移动最快
  local parallaxFactors = {
    1.0,  -- layer_01（最近）——100% 速度
    1.0,  -- layer_02
    0.8,  -- layer_03
    0.6,  -- layer_04
    0.4,  -- layer_05
    0.2,  -- layer_06
    0.1   -- layer_07（最远）——10% 速度
  }

  -- 定义个别层的垂直偏移（仅第 1 层需要调整）
  local verticalOffsets = {
    -290, -- layer_01 需要上移 290 像素
    0,    -- layer_02
    0,    -- layer_03
    0,    -- layer_04
    0,    -- layer_05
    0,    -- layer_06
    0     -- layer_07
  }

  -- 加载全部 7 层
  for i = 1, 7 do
    local layerNum = string.format("%02d", i)
    local layer = {
      image = love.graphics.newImage("eyes/bg/layer_" .. layerNum .. ".png"),
      parallaxFactor = parallaxFactors[i],
      verticalOffset = verticalOffsets[i],
      horizontalOffset = 0,
      -- 第 7 层在概念上视为双倍宽度
      effectiveWidth = (i == 7) and (self.width * 2) or self.width
    }
    table.insert(self.layers, layer)
  end
end

---根据经过的时间更新各层位置
---@param dt number 帧间隔时间（秒）
function background:update(dt)
  -- 更新基础水平偏移
  self.offset = self.offset + self.scrollSpeed * dt

  -- 根据各层的视差系数与有效宽度更新其水平位置
  for _, layer in ipairs(self.layers) do
    layer.horizontalOffset = (self.offset * layer.parallaxFactor) % layer.effectiveWidth
  end
end

---绘制背景各层
function background:draw()
  local screenWidth = love.graphics.getWidth()
  local screenHeight = love.graphics.getHeight()

  -- 计算在保持纵横比的前提下适配屏幕所需的缩放系数
  local scaleX = screenWidth / self.width
  local scaleY = screenHeight / self.height

  -- 根据所选缩放模式确定缩放系数
  local scale
  if self.scaleMode == "contain" then
    scale = math.min(scaleX, scaleY)  -- 确保整张图都能显示
  else -- "cover" 模式
    scale = math.max(scaleX, scaleY)  -- 确保填满整个屏幕
  end

  -- 应用最大缩放限制
  scale = math.min(scale, self.maxScale)

  -- 计算缩放后的尺寸
  local scaledWidth = self.width * scale
  local scaledHeight = self.height * scale

  -- 左下角对齐的坐标
  local alignX = 0
  local alignY = screenHeight - scaledHeight

  -- 从后往前绘制各层（最远到最近）
  for i = #self.layers, 1, -1 do
    local layer = self.layers[i]
    -- 将位置取整到整数像素，避免画面抖动/闪烁
    local x = math.floor(alignX - layer.horizontalOffset * scale)
    local y = math.floor(alignY + (layer.verticalOffset * scale))

    -- 绘制前重置颜色
    love.graphics.setColor(1, 1, 1)

    if i == 7 then -- 对第 7 层（最远背景）做特殊处理
      -- 计算水平方向需要重复多少次
      local repsX = math.ceil(screenWidth / scaledWidth) + 2 -- +2 以确保过渡平滑

      for repX = 0, repsX do
        -- 计算本次重复的位置并取整
        local repX_pos = math.floor(x + (repX * scaledWidth * 2))

        -- 绘制图片部分（概念双倍宽度的前半部分）
        love.graphics.draw(
          layer.image,
          repX_pos,
          y,
          0,
          scale,
          scale
        )

        -- 绘制纯色矩形部分（概念双倍宽度的后半部分）
        love.graphics.setColor(17/255, 13/255, 18/255) -- #110D12
        love.graphics.rectangle(
          "fill",
          repX_pos + scaledWidth,
          y,
          scaledWidth,
          scaledHeight
        )

        -- 重置颜色
        love.graphics.setColor(1, 1, 1)
      end
    else
      -- 普通层——计算水平方向需要重复多少次
      local repsX = math.ceil(screenWidth / scaledWidth) + 1

      -- 为普通层绘制所需的水平重复
      for repX = 0, repsX - 1 do
        -- 将每次重复的位置取整到整数像素
        local repX_pos = math.floor(x + repX * scaledWidth)
        love.graphics.draw(
          layer.image,
          repX_pos,
          y,
          0,
          scale,
          scale
        )
      end
    end
  end
end

---设置水平滚动速度
---@param speed number 新的滚动速度（像素/秒）
function background:setSpeed(speed)
  self.scrollSpeed = speed
end

---设置缩放模式与最大缩放系数
---@param mode string "contain" 或 "cover" 缩放模式
---@param maxScale number 最大缩放系数
function background:setScaling(mode, maxScale)
  self.scaleMode = mode or self.scaleMode
  self.maxScale = maxScale or self.maxScale
end

return background
