---@class TetrisRenderer
---@field load fun()
---@field draw fun()
local renderer = {}

local game = require("tetris")
local colors = game.colors
local shapes = game.shapes
local COLUMNS = game.columns
local ROWS = game.rows
local CELL_SIZE = 32

local fontTitle
local fontLarge
local fontMedium
local fontSmall

local function colorFor(kind)
  return colors[kind] or colors.text
end

local function drawBlock(x, y, size, color, alpha)
  love.graphics.setColor(color[1], color[2], color[3], alpha or 1)
  love.graphics.rectangle("fill", x + 1, y + 1, size - 2, size - 2, 5, 5)
  if not alpha or alpha >= 1 then
    love.graphics.setColor(1, 1, 1, 0.16)
    love.graphics.rectangle("line", x + 2, y + 2, size - 4, size - 4, 4, 4)
  end
end

local function drawPanel(x, y, width, height)
  love.graphics.setColor(colors.panel)
  love.graphics.rectangle("fill", x, y, width, height, 14, 14)
  love.graphics.setColor(colors.panelEdge)
  love.graphics.rectangle("line", x, y, width, height, 14, 14)
end

local function drawNextPreview(x, y, width, kind)
  love.graphics.setFont(fontSmall)
  love.graphics.setColor(colors.muted)
  love.graphics.print("NEXT", x, y)

  local previewSize = 23
  local startX = x + (width - previewSize * 4) / 2
  local startY = y + 25
  local shape = shapes[kind]
  for row = 1, 4 do
    for column = 1, 4 do
      if shape[row]:sub(column, column) == "#" then
        drawBlock(startX + (column - 1) * previewSize, startY + (row - 1) * previewSize,
          previewSize, colorFor(kind))
      end
    end
  end
end

local function drawBoard(boardX, boardY, state)
  local boardWidth = COLUMNS * CELL_SIZE
  local boardHeight = ROWS * CELL_SIZE

  love.graphics.setColor(colors.panelEdge)
  love.graphics.rectangle("fill", boardX - 5, boardY - 5, boardWidth + 10, boardHeight + 10, 12, 12)
  love.graphics.setColor(colors.board)
  love.graphics.rectangle("fill", boardX, boardY, boardWidth, boardHeight)

  for row = 1, ROWS do
    for column = 1, COLUMNS do
      local x = boardX + (column - 1) * CELL_SIZE
      local y = boardY + (row - 1) * CELL_SIZE
      love.graphics.setColor(colors.grid)
      love.graphics.rectangle("line", x, y, CELL_SIZE, CELL_SIZE)
      if state.board[row][column] then
        drawBlock(x, y, CELL_SIZE, colorFor(state.board[row][column]))
      end
    end
  end

  if state.piece then
    local piece = state.piece
    local ghostY = piece.y
    while game.canPlace(piece.matrix, piece.x, ghostY + 1) do
      ghostY = ghostY + 1
    end

    for row = 1, 4 do
      for column = 1, 4 do
        if piece.matrix[row][column] then
          local x = boardX + (piece.x + column - 2) * CELL_SIZE
          local ghostBlockY = boardY + (ghostY + row - 2) * CELL_SIZE
          if ghostY ~= piece.y and ghostBlockY >= boardY then
            drawBlock(x, ghostBlockY, CELL_SIZE, colorFor(piece.kind), 0.25)
          end
          local blockY = boardY + (piece.y + row - 2) * CELL_SIZE
          if blockY >= boardY then
            drawBlock(x, blockY, CELL_SIZE, colorFor(piece.kind))
          end
        end
      end
    end
  end
end

local function drawSidePanels(boardX, boardY, boardWidth, boardHeight, screenWidth, state)
  local panelWidth = 190
  local panelHeight = 142
  local leftX = boardX - panelWidth - 26
  local rightX = boardX + boardWidth + 26

  if leftX >= 20 then
    drawPanel(leftX, boardY, panelWidth, panelHeight)
    drawNextPreview(leftX + 18, boardY + 18, panelWidth - 36, state.queue[1])

    drawPanel(leftX, boardY + panelHeight + 16, panelWidth, 150)
    love.graphics.setFont(fontSmall)
    love.graphics.setColor(colors.muted)
    love.graphics.print("CONTROLS", leftX + 18, boardY + panelHeight + 34)
    love.graphics.setColor(colors.text)
    love.graphics.print("<- -> / A D  Move", leftX + 18, boardY + panelHeight + 61)
    love.graphics.print("Up / X / Z  Rotate", leftX + 18, boardY + panelHeight + 84)
    love.graphics.print("Down  Soft drop", leftX + 18, boardY + panelHeight + 107)
    love.graphics.print("Space  Hard drop", leftX + 18, boardY + panelHeight + 130)
  end

  if rightX + panelWidth <= screenWidth - 20 then
    drawPanel(rightX, boardY, panelWidth, boardHeight)
    love.graphics.setFont(fontSmall)
    love.graphics.setColor(colors.muted)
    love.graphics.print("SCORE", rightX + 20, boardY + 22)
    love.graphics.setFont(fontLarge)
    love.graphics.setColor(colors.text)
    love.graphics.printf(tostring(state.score), rightX + 20, boardY + 49, panelWidth - 40, "left")

    love.graphics.setFont(fontSmall)
    love.graphics.setColor(colors.muted)
    love.graphics.print("LINES", rightX + 20, boardY + 105)
    love.graphics.print("LEVEL", rightX + 105, boardY + 105)
    love.graphics.setFont(fontMedium)
    love.graphics.setColor(colors.text)
    love.graphics.print(tostring(state.lines), rightX + 20, boardY + 128)
    love.graphics.print(tostring(state.level), rightX + 105, boardY + 128)

    if state.clearTimer > 0 then
      love.graphics.setFont(fontMedium)
      love.graphics.setColor(colors.accent)
      love.graphics.printf(state.lastClear == 4 and "TETRIS!" or "NICE!", rightX + 20,
        boardY + 185, panelWidth - 40, "center")
    end

    love.graphics.setFont(fontSmall)
    love.graphics.setColor(colors.muted)
    love.graphics.print("P  Pause", rightX + 20, boardY + boardHeight - 67)
    love.graphics.print("R  Restart", rightX + 20, boardY + boardHeight - 42)
  end
end

function renderer.load()
  fontTitle = love.graphics.newFont(32)
  fontLarge = love.graphics.newFont(27)
  fontMedium = love.graphics.newFont(20)
  fontSmall = love.graphics.newFont(14)
end

function renderer.draw()
  local state = game.getState()
  love.graphics.clear(colors.background[1], colors.background[2], colors.background[3], 1)
  local screenWidth, screenHeight = love.graphics.getDimensions()
  local maxCellByHeight = math.floor((screenHeight - 150) / ROWS)
  local maxCellByWidth = math.floor((screenWidth - 460) / (COLUMNS + 0.6))
  if screenWidth < 760 then
    maxCellByWidth = math.floor((screenWidth - 36) / COLUMNS)
  end
  CELL_SIZE = math.max(16, math.min(32, maxCellByHeight, maxCellByWidth))

  local boardWidth = COLUMNS * CELL_SIZE
  local boardHeight = ROWS * CELL_SIZE
  local boardX = math.floor((screenWidth - boardWidth) / 2)
  local boardY = math.floor((screenHeight - boardHeight) / 2 + 20)

  love.graphics.setFont(fontTitle)
  love.graphics.setColor(colors.text)
  love.graphics.printf("TETRIS", boardX - 4, math.max(14, boardY - 54), boardWidth + 8, "center")
  love.graphics.setFont(fontSmall)
  love.graphics.setColor(colors.muted)
  love.graphics.printf("Stack, clear lines, beat your best", boardX - 100, math.max(52, boardY - 22),
    boardWidth + 200, "center")

  drawBoard(boardX, boardY, state)
  drawSidePanels(boardX, boardY, boardWidth, boardHeight, screenWidth, state)

  if state.paused or state.gameOver then
    love.graphics.setColor(0.015, 0.025, 0.045, 0.78)
    love.graphics.rectangle("fill", boardX, boardY, boardWidth, boardHeight)
    love.graphics.setFont(fontTitle)
    love.graphics.setColor(state.gameOver and colors.Z or colors.text)
    love.graphics.printf(state.gameOver and "GAME OVER" or "PAUSED", boardX, boardY + boardHeight / 2 - 28,
      boardWidth, "center")
    love.graphics.setFont(fontSmall)
    love.graphics.setColor(colors.muted)
    local hint = state.gameOver and "Press R to play again" or "Press P to resume"
    love.graphics.printf(hint, boardX, boardY + boardHeight / 2 + 18, boardWidth, "center")
  end
end

return renderer
