--[[
================================================================================
 eyes/utils/vector.lua —— 二维向量工具模块
================================================================================
 作用：
   提供一组轻量的二维向量数学函数，供眼睛场景的各个模块复用，包括：
     - 计算两点距离
     - 向量归一化（单位化）
     - 向量缩放
     - 限制向量最大长度（截断）
     - 计算向量长度

 约定：所有向量均以独立的 x、y 两个数值表示（而非表），便于直接传参与返回。
================================================================================
--]]

---@class Vector 向量运算工具模块
local vector = {}

---计算两点之间的距离
---@param x1 number 第一个点的 x 坐标
---@param y1 number 第一个点的 y 坐标
---@param x2 number 第二个点的 x 坐标
---@param y2 number 第二个点的 y 坐标
---@return number distance 两点之间的距离
function vector.distance(x1, y1, x2, y2)
  local dx, dy = x2 - x1, y2 - y1
  return math.sqrt(dx * dx + dy * dy)
end

---归一化一个向量（使其长度为 1）
---@param x number 向量的 x 分量
---@param y number 向量的 y 分量
---@return number nx 归一化后的 x 分量
---@return number ny 归一化后的 y 分量
function vector.normalize(x, y)
  local length = math.sqrt(x * x + y * y)
  if length > 0 then
    return x / length, y / length
  else
    -- 零向量无法归一化，返回 0,0
    return 0, 0
  end
end

---按给定系数缩放向量
---@param x number 向量的 x 分量
---@param y number 向量的 y 分量
---@param scale number 缩放系数
---@return number sx 缩放后的 x 分量
---@return number sy 缩放后的 y 分量
function vector.scale(x, y, scale)
  return x * scale, y * scale
end

---将向量长度限制在最大值以内（超过则截断，方向不变）
---@param x number 向量的 x 分量
---@param y number 向量的 y 分量
---@param maxLength number 允许的最大长度
---@return number cx 截断后的 x 分量
---@return number cy 截断后的 y 分量
function vector.clamp(x, y, maxLength)
  local length = math.sqrt(x * x + y * y)
  if length > maxLength and length > 0 then
    local factor = maxLength / length
    return x * factor, y * factor
  else
    return x, y
  end
end

---获取向量的长度（模）
---@param x number 向量的 x 分量
---@param y number 向量的 y 分量
---@return number length 向量的长度
function vector.length(x, y)
  return math.sqrt(x * x + y * y)
end

return vector
