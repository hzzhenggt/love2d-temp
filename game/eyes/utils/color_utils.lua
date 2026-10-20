--[[
================================================================================
 eyes/utils/color_utils.lua —— 颜色工具模块
================================================================================
 作用：
   集中管理眼睛场景使用的调色板，并提供常用的颜色处理函数，包括：
     - 构造颜色、转换为 LÖVE 颜色格式
     - 两色之间的线性插值（lerp）
     - 变亮 / 变暗 / 调整透明度
     - 按名称从调色板中取色（支持 "eyes.normal.iris" 这类嵌套路径）

 颜色格式说明：
   LÖVE 11+ 的颜色分量取值范围为 0~1，以数组 {r, g, b, a} 表示，a 为可选透明度。
================================================================================
--]]

---@class ColorUtils 颜色处理与管理工具函数集合
local colorUtils = {}

-- 应用中各部分使用的调色板
colorUtils.palettes = {
  -- 眼球主体颜色
  main = {
    white = { 1.0, 1.0, 1.0 },       -- 白色
    shadedWhite = { 0.8, 0.8, 0.9 }, -- 带阴影的白色（偏冷）
    lightPink = { 1.0, 0.92, 0.92 }, -- 浅粉色
  },

  -- 虹膜颜色
  eyes = {
    normal = { iris = { 0.0, 0.5, 0.95 } }, -- 蓝色（常态）
    online = { iris = { 0.0, 0.8, 0.2 } },  -- 绿色（在线状态）
    touched = { iris = { 0.6, 0.0, 0.0 } }  -- 暗红色（被触碰时）
  },

  -- 眼睛反光颜色
  reflections = {
    main = { 1.0, 0.95, 0.8 },  -- 暖黄色
    core = { 1.0, 1.0, 0.9 }    -- 明亮的黄白色
  }
}

---构造一个颜色对象
---@param r number 红色分量（0-1）
---@param g number 绿色分量（0-1）
---@param b number 蓝色分量（0-1）
---@param a? number 透明度分量（0-1），默认为 1
---@return table color 颜色对象 {r, g, b, a}
function colorUtils.rgb(r, g, b, a)
  return {r, g, b, a or 1}
end

---将颜色转换为 LÖVE 格式（数值数组）
---@param color table 颜色表 {r, g, b, a} 或 {r, g, b}
---@return table color 符合 LÖVE 约定的颜色格式 {r, g, b, a}
function colorUtils.toLoveColor(color)
  -- 如果已是正确的数组格式，直接补全 alpha 后返回
  if type(color[1]) == "number" then
    return {color[1], color[2], color[3], color[4] or 1}
  end

  return {color.r or color[1], color.g or color[2], color.b or color[3], color.a or color[4] or 1}
end

---在两个颜色之间按系数（0~1）做线性插值
---@param color1 table 起始颜色 {r, g, b} 或 {r, g, b, a}
---@param color2 table 目标颜色 {r, g, b} 或 {r, g, b, a}
---@param factor number 插值系数（0 = color1，1 = color2）
---@return table 插值后的颜色 {r, g, b, a}
function colorUtils.lerp(color1, color2, factor)
  factor = math.max(0, math.min(1, factor)) -- 将系数限制在 0 到 1 之间

  -- 必要时先转换为数组格式
  color1 = colorUtils.toLoveColor(color1)
  color2 = colorUtils.toLoveColor(color2)

  local r = color1[1] + (color2[1] - color1[1]) * factor
  local g = color1[2] + (color2[2] - color1[2]) * factor
  local b = color1[3] + (color2[3] - color1[3]) * factor

  -- 若存在 alpha 分量则一并插值
  local a = 1
  if color1[4] and color2[4] then
    a = color1[4] + (color2[4] - color1[4]) * factor
  elseif color1[4] then
    a = color1[4]
  elseif color2[4] then
    a = color2[4]
  end

  return {r, g, b, a}
end

---将颜色按指定幅度变亮（向白色靠拢）
---@param color table 要变亮的颜色 {r, g, b} 或 {r, g, b, a}
---@param amount number 变亮幅度（0-1）
---@return table 变亮后的颜色 {r, g, b, a}
function colorUtils.lighten(color, amount)
  color = colorUtils.toLoveColor(color)
  local white = {1, 1, 1, color[4] or 1}
  return colorUtils.lerp(color, white, amount)
end

---将颜色按指定幅度变暗（向黑色靠拢）
---@param color table 要变暗的颜色 {r, g, b} 或 {r, g, b, a}
---@param amount number 变暗幅度（0-1）
---@return table 变暗后的颜色 {r, g, b, a}
function colorUtils.darken(color, amount)
  color = colorUtils.toLoveColor(color)
  local black = {0, 0, 0, color[4] or 1}
  return colorUtils.lerp(color, black, amount)
end

---调整颜色的透明度
---@param color table 要调整的颜色 {r, g, b} 或 {r, g, b, a}
---@param alpha number 新的透明度值（0-1）
---@return table 调整透明度后的颜色 {r, g, b, a}
function colorUtils.withAlpha(color, alpha)
  color = colorUtils.toLoveColor(color)
  return {color[1], color[2], color[3], alpha}
end

---按名称从调色板中获取颜色
---@param paletteName string 调色板名称
---@param colorName string 调色板中颜色的名称
---@return table|nil color 对应颜色；未找到时返回 nil
function colorUtils.getColor(paletteName, colorName)
  local palette = colorUtils.palettes[paletteName]
  if not palette then
    return nil
  end

  -- 处理嵌套路径（例如 "eyes.normal.iris"）
  if colorName:find("%.") then
    local parts = {}
    for part in colorName:gmatch("[^%.]+") do
      table.insert(parts, part)
    end

    local current = palette
    for i = 1, #parts do
      if type(current) ~= "table" then
        return nil
      end
      current = current[parts[i]]
      if not current then
        return nil
      end
    end

    return colorUtils.toLoveColor(current)
  end

  local color = palette[colorName]
  if color then
    return colorUtils.toLoveColor(color)
  end

  return nil
end

---获取 main 调色板中的颜色（getColor("main", name) 的快捷方式）
---@param name string main 调色板中颜色的名称
---@return table|nil color 对应颜色；未找到时返回 nil
function colorUtils.getMainColor(name)
  return colorUtils.getColor("main", name)
end

return colorUtils
