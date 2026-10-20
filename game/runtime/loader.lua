--[[
================================================================================
 runtime/loader.lua —— 原生库加载器
================================================================================
 作用：
   为 LÖVE 游戏加载平台相关的原生动态库（.dll / .so），并提供 HTTPS 库的
   按需加载逻辑。不同操作系统、不同 CPU 架构需要不同的库文件，本模块负责：
     1. 探测当前系统信息（操作系统、架构、位宽等）。
     2. 根据系统信息定位对应平台的子目录。
     3. 把库文件从只读的游戏资源目录复制到可写的存档目录后再加载。
     4. 根据 LÖVE 版本与平台，决定如何加载 HTTPS 库。

 背景知识：
   LÖVE 的游戏资源目录通常是只读的（尤其是打包成 .love 之后），
   而加载原生库需要一个真实的可写文件路径，因此需要先复制到存档目录。
================================================================================
--]]

---@class Loader
---LÖVE 游戏的原生库加载器
local M = {}

---获取系统架构信息
---@return table systemInfo 包含操作系统与架构详情的表
---@return string systemInfo.os 操作系统名称（小写）
---@return string systemInfo.arch 架构名称
---@return boolean systemInfo.is64bit 系统是否为 64 位
---@return boolean systemInfo.isArm 是否为 ARM 架构
---@return boolean systemInfo.isX86 是否为 x86 架构
local function getSystemInfo()
  local os = love.system.getOS():lower():gsub("%s+", "")
  local ffi = require("ffi")
  local arch = ffi.arch
  local is64bit = ffi.abi("64bit")
  local isArm = arch:match("^arm")
  local isX86 = arch:match("^x86") or arch:match("^x64")

  return {
    os = os,
    arch = arch,
    is64bit = is64bit,
    isArm = isArm,
    isX86 = isX86,
  }
end

---确定原生库所在的平台相关子目录
---@param sysInfo table 由 getSystemInfo() 返回的系统信息
---@return string|nil platformSubdir 平台相关子目录；若平台不支持则返回 nil
local function getPlatformSubdir(sysInfo)
  if sysInfo.os == "android" then
    if sysInfo.isArm then
      return sysInfo.is64bit and sysInfo.os .. "/arm64-v8a" or sysInfo.os .. "/armeabi-v7a"
    end
  elseif sysInfo.os == "linux" then
    if sysInfo.isX86 and sysInfo.is64bit then
      return sysInfo.os .. "/x86_64"
    end
  elseif sysInfo.os == "osx" then
    return sysInfo.os
  elseif sysInfo.os == "windows" then
    if sysInfo.isX86 then
      return sysInfo.is64bit and sysInfo.os .. "/win64" or sysInfo.os .. "/win32"
    end
  end
  return nil
end

---从对应平台的子目录加载原生库
---@param libraryName string 库名称（不含扩展名）
---@return table|nil library 已加载的库模块；失败时返回 nil
function M.loadNativeLibrary(libraryName)
  local sysInfo = getSystemInfo()
  local extension = sysInfo.os == "windows" and ".dll" or ".so"
  local libraryFile = libraryName .. extension
  local subdir = getPlatformSubdir(sysInfo)
  if not subdir then
    return nil
  end

  local assetFile = "runtime/" .. libraryName .. "/" .. subdir .. "/" .. libraryFile
  local saveFile = love.filesystem.getSaveDirectory() .. "/" .. libraryFile
  print("Asset File:", assetFile)
  print("Save File:", saveFile)

  -- 检查当前架构对应的库文件是否存在于游戏资源目录中
  if not love.filesystem.getInfo(assetFile) then
    error("Missing: " .. assetFile)
  else
    print("Found: " .. assetFile)
  end

  -- 把库文件从（只读的）游戏资源目录复制到（可写的）存档目录
  local libraryData = love.filesystem.read(assetFile)
  if love.filesystem.write(libraryFile, libraryData) then
    print("Copied: " .. assetFile .. " -> " .. saveFile)
  else
    error("Failed: " .. assetFile .. " -> " .. saveFile)
  end
  libraryData = nil

  -- 把存档目录加入 package.cpath，使 require 能找到刚复制的原生库
  package.cpath = package.cpath .. ";" .. love.filesystem.getSaveDirectory() .. "/?." .. extension:sub(2)
  print("package.cpath: " .. package.cpath)

  -- 现在像加载普通 Lua 模块一样加载它
  local status, result = pcall(require, libraryName)
  if status then
    print(libraryFile .. ": loaded")
    return result
  else
    print(libraryFile .. ": failed to load")
    return nil
  end
end

---根据当前 LÖVE 版本与平台加载合适的 HTTPS 库
---@return table|nil https HTTPS 库模块；在 Web 平台或不可用时返回 nil
function M.loadHTTPS()
  local major = love.getVersion()
  local os = love.system.getOS()

  if os == "Web" then
    -- Web 平台（love.js）不支持原生 HTTPS 库
    return nil
  elseif major >= 12 then
    -- LÖVE 12 及以上内置了 https 模块，可直接 require
    return require("https")
  else
    -- 旧版本需要手动加载平台相关的原生 HTTPS 库
    return M.loadNativeLibrary("https")
  end
end

return M
