--[[
================================================================================
 eyes/shadows.lua —— 眼睛阴影模块
================================================================================
 作用：
   在每只眼睛下方的固定高度处绘制一个椭圆投影，用于增强悬浮眼球的立体感。
   阴影会根据眼睛与阴影位置之间的距离做大小缩放（眼睛越远阴影越小），
   并通过多层逐渐变淡的椭圆叠加来模拟柔和的模糊边缘。

 关键参数：
     distanceFromBottom  阴影距屏幕底部的固定距离
     color               阴影颜色（黑色 + 较低透明度）
     scaleFactor         阴影相对眼睛尺寸的基础缩放
     scaleDistance       用于计算缩放的参考距离
     minScale            最小缩放系数
================================================================================
--]]

---@class Shadows 绘制眼睛阴影的模块
local shadows = {
  -- 阴影配置
  distanceFromBottom = 200,  -- 距屏幕底部的固定位置
  color = {0, 0, 0, 0.1},    -- 阴影颜色（黑色，约 10% 不透明度）
  scaleFactor = 0.7,         -- 相对眼睛尺寸的基础阴影缩放
  scaleDistance = 300,       -- 用于缩放阴影大小的参考距离
  minScale = 0.75,           -- 最小缩放系数
  blur = 8,                  -- 阴影模糊量（像素）
  yOffset = 0,               -- 将在 update 中计算
}

-- 私有函数
---在一只眼睛下方绘制阴影
---@param eyeX number 眼睛的 x 坐标
---@param eyeY number 眼睛的 y 坐标
---@param eyeSize number 眼睛的尺寸
---@param shadowY number 阴影的 y 坐标
local function drawShadow(eyeX, eyeY, eyeSize, shadowY)
  -- 计算眼睛与阴影位置之间的距离
  local distance = math.abs(eyeY - shadowY)

  -- 根据距离计算阴影缩放：眼睛离阴影位置越远，阴影越小
  local distanceRatio = math.min(1, distance / shadows.scaleDistance)
  local shadowScale = shadows.scaleFactor * (shadows.minScale + (1 - shadows.minScale) * (1 - distanceRatio))

  -- 计算阴影的宽度与高度（椭圆形，扁平）
  local shadowWidth = eyeSize * 1.75 * shadowScale
  local shadowHeight = eyeSize * 0.25 * shadowScale

  -- 保存当前的混合模式与着色器
  local prevBlendMode = love.graphics.getBlendMode()
  local prevShader = love.graphics.getShader()

  -- 设置混合模式以正确进行 alpha 混合
  love.graphics.setBlendMode("alpha", "premultiplied")
  love.graphics.setShader()

  -- 将阴影绘制为一个边缘自然淡出的模糊椭圆
  local blurSteps = 10  -- 增大层数以获得更平滑的渐变
  local maxScale = 1.25 -- 最外层模糊的最大缩放系数

  -- 从最内层（最深）向最外层（最浅）绘制
  -- 先用基础不透明度绘制主体阴影椭圆
  love.graphics.setColor(shadows.color[1], shadows.color[2], shadows.color[3], shadows.color[4])
  love.graphics.ellipse("fill", eyeX, shadowY, shadowWidth, shadowHeight)

  -- 再以递减的不透明度绘制模糊边缘
  for i = 1, blurSteps do
    -- 计算从内到外的进度（0 到 1）
    local progress = i / blurSteps

    -- 缩放随着向外推进而增大
    local scaleIncrement = progress * (maxScale - 1.0)
    local currentScale = 1.0 + scaleIncrement

    -- 不透明度随着向外推进而减小——使用非线性衰减以获得更自然的效果
    -- 幂函数让边缘附近的衰减更快
    local opacityFactor = math.pow(1.0 - progress, 2.0)
    local opacity = shadows.color[4] * opacityFactor * 0.8

    -- 用计算出的不透明度设置颜色
    love.graphics.setColor(shadows.color[1], shadows.color[2], shadows.color[3], opacity)

    -- 绘制这一层模糊椭圆
    love.graphics.ellipse("fill", eyeX, shadowY,
                         shadowWidth * currentScale,
                         shadowHeight * currentScale)
  end

  -- 恢复绘图状态
  love.graphics.setLineWidth(1)
  love.graphics.setBlendMode(prevBlendMode)
  love.graphics.setShader(prevShader)
end

-- 公共函数
---初始化阴影模块
function shadows.load()
  -- 目前无需加载任何资源，保留此函数以与其他模块保持一致
end

---根据窗口高度更新阴影位置
---@param dt number 距上一帧的时间
---@param windowHeight number 当前窗口高度
function shadows.update(dt, windowHeight)
  -- 根据窗口高度计算阴影的 y 位置
  shadows.yOffset = windowHeight - shadows.distanceFromBottom
end

---为一只眼睛绘制阴影
---@param eyeX number 眼睛的 x 坐标
---@param eyeY number 眼睛的 y 坐标
---@param eyeSize number 眼睛的尺寸
function shadows.draw(eyeX, eyeY, eyeSize)
  drawShadow(eyeX, eyeY, eyeSize, shadows.yOffset)
end

return shadows
