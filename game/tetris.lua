---@class Tetris
---@field colors table
---@field shapes table
---@field columns number
---@field rows number
---@field load fun()
---@field update fun(dt: number, softDropping: boolean)
---@field getState fun(): table
---@field canPlace fun(matrix: table, x: number, y: number): boolean
---@field restart fun()
---@field moveHorizontal fun(direction: number)
---@field rotate fun(clockwise: boolean)
---@field softDrop fun()
---@field hardDrop fun()
---@field togglePause fun()
---@type Tetris
local tetris = {}

local COLUMNS = 10
local ROWS = 20
local GRAVITY_INTERVAL = 0.8

local colors = {
  background = {0.035, 0.055, 0.09},
  panel = {0.075, 0.105, 0.16},
  panelEdge = {0.16, 0.22, 0.31},
  board = {0.045, 0.065, 0.1},
  grid = {0.11, 0.14, 0.2},
  text = {0.91, 0.94, 0.98},
  muted = {0.57, 0.64, 0.74},
  accent = {0.3, 0.88, 0.78},
  I = {0.24, 0.83, 0.91},
  J = {0.28, 0.46, 0.94},
  L = {0.98, 0.61, 0.27},
  O = {0.98, 0.83, 0.31},
  S = {0.36, 0.82, 0.49},
  T = {0.71, 0.45, 0.91},
  Z = {0.94, 0.36, 0.42},
}

local shapes = {
  I = {"....", "####", "....", "...."},
  J = {"#...", "###.", "....", "...."},
  L = {"..#.", "###.", "....", "...."},
  O = {".##.", ".##.", "....", "...."},
  S = {".##.", "##..", "....", "...."},
  T = {".#..", "###.", "....", "...."},
  Z = {"##..", ".##.", "....", "...."},
}

local state = {}

tetris.colors = colors
tetris.shapes = shapes
tetris.columns = COLUMNS
tetris.rows = ROWS

local function emptyRow()
  local row = {}
  for column = 1, COLUMNS do
    row[column] = false
  end
  return row
end

local function copyShape(shape)
  local matrix = {}
  for row = 1, 4 do
    matrix[row] = {}
    for column = 1, 4 do
      matrix[row][column] = shape[row]:sub(column, column) == "#"
    end
  end
  return matrix
end

local function newBoard()
  local board = {}
  for row = 1, ROWS do
    board[row] = emptyRow()
  end
  return board
end

local function refillBag()
  local bag = {"I", "J", "L", "O", "S", "T", "Z"}
  for index = #bag, 2, -1 do
    local other = math.random(index)
    bag[index], bag[other] = bag[other], bag[index]
  end
  for _, kind in ipairs(bag) do
    table.insert(state.queue, kind)
  end
end

local function takeNextKind()
  while #state.queue < 5 do
    refillBag()
  end
  return table.remove(state.queue, 1)
end

local function canPlace(matrix, x, y)
  for row = 1, 4 do
    for column = 1, 4 do
      if matrix[row][column] then
        local boardX = x + column - 1
        local boardY = y + row - 1
        if boardX < 1 or boardX > COLUMNS or boardY > ROWS then
          return false
        end
        if boardY >= 1 and state.board[boardY][boardX] then
          return false
        end
      end
    end
  end
  return true
end

tetris.canPlace = canPlace

local function spawnPiece()
  local kind = takeNextKind()
  state.piece = {
    kind = kind,
    matrix = copyShape(shapes[kind]),
    x = 4,
    y = 0,
  }
  state.gravityTimer = 0
  if not canPlace(state.piece.matrix, state.piece.x, state.piece.y) then
    state.gameOver = true
  end
end

local function movePiece(offsetX, offsetY)
  local piece = state.piece
  if canPlace(piece.matrix, piece.x + offsetX, piece.y + offsetY) then
    piece.x = piece.x + offsetX
    piece.y = piece.y + offsetY
    return true
  end
  return false
end

local function rotateMatrix(matrix, clockwise)
  local rotated = {}
  for row = 1, 4 do
    rotated[row] = {}
    for column = 1, 4 do
      if clockwise then
        rotated[row][column] = matrix[5 - column][row]
      else
        rotated[row][column] = matrix[column][5 - row]
      end
    end
  end
  return rotated
end

local function clearLines()
  local cleared = 0
  local rowIndex = ROWS
  while rowIndex >= 1 do
    local full = true
    for column = 1, COLUMNS do
      if not state.board[rowIndex][column] then
        full = false
        break
      end
    end

    if full then
      table.remove(state.board, rowIndex)
      table.insert(state.board, 1, emptyRow())
      cleared = cleared + 1
    else
      rowIndex = rowIndex - 1
    end
  end

  if cleared > 0 then
    local linePoints = {0, 100, 300, 500, 800}
    state.score = state.score + linePoints[cleared] * state.level
    state.lines = state.lines + cleared
    state.level = math.floor(state.lines / 10) + 1
    state.lastClear = cleared
    state.clearTimer = 0.7
  end
end

local function lockPiece()
  local piece = state.piece
  local toppedOut = false
  for row = 1, 4 do
    for column = 1, 4 do
      if piece.matrix[row][column] then
        local boardX = piece.x + column - 1
        local boardY = piece.y + row - 1
        if boardY < 1 then
          toppedOut = true
        else
          state.board[boardY][boardX] = piece.kind
        end
      end
    end
  end

  if toppedOut then
    state.gameOver = true
    return
  end

  clearLines()
  spawnPiece()
end

local function resetGame()
  state = {
    board = newBoard(),
    queue = {},
    score = 0,
    lines = 0,
    level = 1,
    gravityTimer = 0,
    paused = false,
    gameOver = false,
    lastClear = 0,
    clearTimer = 0,
  }
  refillBag()
  spawnPiece()
end

function tetris.load()
  math.randomseed(os.time())
  resetGame()
end

function tetris.getState()
  return state
end

function tetris.restart()
  resetGame()
end

function tetris.moveHorizontal(direction)
  if not state.paused and not state.gameOver then
    movePiece(direction, 0)
  end
end

function tetris.rotate(clockwise)
  if state.paused or state.gameOver then
    return
  end

  local piece = state.piece
  local rotated = rotateMatrix(piece.matrix, clockwise)
  local offsets = {0, -1, 1, -2, 2}
  for _, offset in ipairs(offsets) do
    if canPlace(rotated, piece.x + offset, piece.y) then
      piece.matrix = rotated
      piece.x = piece.x + offset
      return
    end
  end
end

function tetris.softDrop()
  if state.paused or state.gameOver then
    return
  end

  if movePiece(0, 1) then
    state.score = state.score + 1
    state.gravityTimer = 0
  else
    lockPiece()
  end
end

function tetris.hardDrop()
  if state.paused or state.gameOver then
    return
  end

  local distance = 0
  while movePiece(0, 1) do
    distance = distance + 1
  end
  state.score = state.score + distance * 2
  lockPiece()
end

function tetris.togglePause()
  if not state.gameOver then
    state.paused = not state.paused
  end
end

function tetris.update(dt, softDropping)
  if state.paused or state.gameOver then
    return
  end

  dt = math.min(dt, 0.1)
  state.clearTimer = math.max(0, state.clearTimer - dt)

  local interval = state.level > 1 and math.max(0.08, GRAVITY_INTERVAL * 0.85 ^ (state.level - 1))
    or GRAVITY_INTERVAL
  if softDropping then
    interval = 0.05
  end

  state.gravityTimer = state.gravityTimer + dt
  while state.gravityTimer >= interval and not state.gameOver do
    state.gravityTimer = state.gravityTimer - interval
    if not movePiece(0, 1) then
      lockPiece()
    end
  end
end

return tetris
