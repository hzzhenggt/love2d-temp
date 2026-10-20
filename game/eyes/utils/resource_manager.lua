--[[
================================================================================
 eyes/utils/resource_manager.lua —— 资源管理器
================================================================================
 作用：
   统一负责眼睛场景中各类资源（纹理、着色器、字体）的加载与访问，
   并在加载失败时提供容错处理（例如着色器加载失败时回退到透传着色器）。

 设计要点：
   - 所有资源路径集中定义在 RESOURCE_PATHS 常量中，便于查找与修改。
   - 加载过程使用 pcall 包裹，单个资源失败不会导致整体崩溃。
   - 通过 get 系列方法按名称获取已加载资源。

 调用方式：
   ResourceManager.new():loadAll() 创建并一次性加载全部资源，
   随后用 getTexture / getShader / getFont 取用。
================================================================================
--]]

---@class ResourceManager 负责眼睛模块资源的加载与管理
local ResourceManager = {}
ResourceManager.__index = ResourceManager

-- 资源路径常量（集中维护）
local RESOURCE_PATHS = {
  textures = {
    bloodVeins = "eyes/gfx/blood_veins_100.png", -- 血丝纹理
    iris = "eyes/gfx/iris.png",                   -- 虹膜纹理
    pupil = "eyes/gfx/pupil.png",                 -- 瞳孔纹理
  },
  shaders = {
    eye = "eyes/shaders/eye.glsl",                -- 眼球渐变着色器
  },
  fonts = {
    default = {size = 42},                        -- 默认字体及字号
  }
}

-- 着色器加载失败时使用的回退着色器源码（直接透传颜色）
local FALLBACK_SHADER = [[
  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    return color;
  }
]]

---创建一个新的 ResourceManager
---@return ResourceManager
function ResourceManager.new()
  local self = setmetatable({}, ResourceManager)
  self.resources = {
    textures = {},
    shaders = {},
    fonts = {},
  }
  self.loadErrors = {}
  return self
end

---从路径加载纹理，带错误处理
---@param name string 资源名称
---@param path string 纹理文件路径
---@return love.Image|nil texture 已加载的纹理；加载失败时返回 nil
local function loadTexture(name, path)
  local success, result = pcall(function()
    return love.graphics.newImage(path)
  end)

  if success then
    return result
  else
    print("Error loading texture '" .. name .. "': " .. tostring(result))
    return nil
  end
end

---从路径加载着色器，带错误处理
---@param name string 资源名称
---@param path string 着色器文件路径
---@return love.Shader shader 已加载的着色器；加载失败时返回回退着色器
local function loadShader(name, path)
  local success, result = pcall(function()
    return love.graphics.newShader(path)
  end)

  if success then
    return result
  else
    print("Error loading shader '" .. name .. "': " .. tostring(result))
    -- 返回一个回退着色器，保证后续绘制不会崩溃
    return love.graphics.newShader(FALLBACK_SHADER)
  end
end

---加载 RESOURCE_PATHS.textures 中定义的全部纹理
---@return table<string, love.Image> 已加载的纹理集合
function ResourceManager:loadTextures()
  local textures = {}

  for name, path in pairs(RESOURCE_PATHS.textures) do
    textures[name] = loadTexture(name, path)
  end

  self.resources.textures = textures
  return textures
end

---加载 RESOURCE_PATHS.shaders 中定义的全部着色器
---@return table<string, love.Shader> 已加载的着色器集合
function ResourceManager:loadShaders()
  local shaders = {}

  for name, path in pairs(RESOURCE_PATHS.shaders) do
    shaders[name] = loadShader(name, path)
  end

  self.resources.shaders = shaders
  return shaders
end

---加载 RESOURCE_PATHS.fonts 中定义的全部字体
---@return table<string, love.Font> 已加载的字体集合
function ResourceManager:loadFonts()
  local fonts = {}

  for name, config in pairs(RESOURCE_PATHS.fonts) do
    local success, result = pcall(function()
      return love.graphics.newFont(config.size)
    end)

    if success then
      fonts[name] = result
    else
      print("Error loading font '" .. name .. "': " .. tostring(result))
      fonts[name] = love.graphics.getFont() -- 失败时回退到默认字体
    end
  end

  self.resources.fonts = fonts
  return fonts
end

---加载全部资源
---@return ResourceManager self
function ResourceManager:loadAll()
  self:loadTextures()
  self:loadShaders()
  self:loadFonts()
  return self
end

---按名称获取已加载的纹理资源
---@param name string 纹理名称
---@return love.Image|nil texture 对应纹理；未找到时返回 nil
function ResourceManager:getTexture(name)
  return self.resources.textures[name]
end

---按名称获取已加载的着色器资源
---@param name string 着色器名称
---@return love.Shader|nil shader 对应着色器；未找到时返回 nil
function ResourceManager:getShader(name)
  return self.resources.shaders[name]
end

---按名称获取已加载的字体资源
---@param name string 字体名称
---@return love.Font|nil font 对应字体；未找到时返回 nil
function ResourceManager:getFont(name)
  return self.resources.fonts[name]
end

---将默认字体设置为指定字体
---@param name string 要设为默认的字体名称
function ResourceManager:setDefaultFont(name)
  local font = self:getFont(name)
  if font then
    love.graphics.setFont(font)
  end
end

return ResourceManager
