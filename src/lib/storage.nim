import os, random, json, strformat, tables, sequtils, times, options, strutils

import config
import render
import item, task, note

randomize()

type ItemMap* = OrderedTable[int, Item]

template initItemMap*(size = 64): untyped =
    initOrderedTable[int, Item](size)

let mainAppDir: string = block:
    let taskbookDir = tbConfig.taskbookDirectory
    let defaultAppDir = getHomeDir() / ".taskbook"

    if taskbookDir == "":
        defaultAppDir
    else:
        if not taskbookDir.existsDir():
            render.invalidCustomAppDir(taskbookDir)
            quit(1)
        
        taskbookDir / ".taskbook"

let
    storageDir = mainAppDir / "storage"
    archiveDir = mainAppDir / "archive"
    tempDir = mainAppDir / ".temp"
    archiveFile = archiveDir / "archive.json"
    mainStorageFile = storageDir / "storage.json"

# ensure directories exist
for dir in [mainAppDir, storageDir, archiveDir, tempDir]:
    if not dir.existsDir:
        dir.createDir()

proc cleanTempDir = 
    for entry in walkDir(tempDir):
        if entry.kind == pcFile:
            discard tryRemoveFile(entry.path)
        else:
            removeDir(entry.path)

proc getRandomString(length = 8): string =
    for _ in 0..length:
        let randVal = rand(35)

        # lol this is dumb
        if randVal < 26:
            result.add char(ord('a') + randVal)
        else:
            result.add char(ord('0') + randVal - 26)

proc getTempFile(tempType: string): string =
    let randomString = getRandomString()
    # Original code does some weird shit with basename of mainStorageFile / archiveFile
    # but ultimately arrives to this format, since those values are hardcoded anyway
    # I think this is less convoluted
    let tempFilename = fmt"{tempType}.TEMP-{randomString}.json"
    
    tempDir / tempFilename

# can't just unmarshal, as leading underscores aren't valid idents in Nim
proc jsonToItem(jn: JsonNode): Item = 
    let id = jn["_id"].getInt()
    let date = jn["_date"].getStr()
    let timestamp = jn["_timestamp"].getInt()
    let desc = jn["description"].getStr()
    let isStarred = jn["isStarred"].getBool()
    let boards = jn["boards"].getElems().mapIt(it.getStr())
    let isTask = jn["_isTask"].getBool()
    let isComplete = jn{"isComplete"}.getBool()
    let inProgress = jn{"inProgress"}.getBool(false)

    # Original taskbook - when it updates priorities, sets them as a string
    # for some reason, so we have to be able to handle that
    let priorityJson = jn{"priority"}
    var priority = 1

    if priorityJson != nil and priorityJson.kind == JString:
        priority = priorityJson.getStr().parseInt()
    else:
        priority = priorityJson.getInt()

    if isTask:
        Task(
            id: id,
            date: date,
            timestamp: fromUnix(int64(timestamp / 1000)).local(),
            description: desc,
            isStarred: isStarred,
            boards: boards,
            isTask: isTask,
            isComplete: isComplete,
            priority: priority,
            inProgress: inProgress
        )
    else:
        Item(
            id: id,
            date: date,
            timestamp: fromUnix(int64(timestamp / 1000)).local(),
            description: desc,
            isStarred: isStarred,
            boards: boards,
            isTask: isTask
        )

proc itemToJson(item: Item): JsonNode = 
    result = newJObject()

    result.add("_id", newJInt(item.id))
    result.add("_date", newJString(item.date))
    result.add("_timestamp", newJInt(toUnix(item.timestamp.toTime()) * 1000))
    result.add("description", newJString(item.description))
    result.add("isStarred", newJBool(item.isStarred))

    let boardsNode = newJArray()
    for board in item.boards.mapIt newJString(it):
        boardsNode.add(board)

    result.add("boards", boardsNode)
    result.add("_isTask", newJBool(item.isTask))

    if item.isTask:
        let task = Task(item)
        result.add("isComplete", newJBool(task.isComplete))
        result.add("priority", newJInt(task.priority))
        result.add("inProgress", newJBool(task.inProgress))

var cachedItems = none[OrderedTable[int, Item]]()

proc getItems*(): OrderedTable[int, Item] = 
    if cachedItems.isSome(): return cachedItems.get()

    result = initItemMap()
    if not mainStorageFile.existsFile(): return

    let jsonRes = json.parseFile(mainStorageFile)
    
    for field in jsonRes.fields.keys():
        result.add(parseInt(field), jsonRes[field].jsonToItem())

    cachedItems = some(result)

proc getArchive*(): OrderedTable[int, Item] = 
    result = initItemMap()
    if not archiveFile.existsFile(): return

    let jsonRes = json.parseFile(mainStorageFile)
    
    for field in jsonRes.fields.keys():
        result.add(parseInt(field), jsonRes[field].jsonToItem())

proc setItems*(items: OrderedTable[int, Item]) =
    cachedItems = some(items)
    
    let obj = newJObject();

    for i in items.keys():
        obj.add($i, items[i].itemToJson())

    let tempStorageFile = getTempFile("storage")
    writeFile(tempStorageFile, pretty(obj, 4))
    discard tryRemoveFile(mainStorageFile)
    moveFile(tempStorageFile, mainStorageFile)

proc setArchive*(items: OrderedTable[int, Item]) =
    let obj = newJObject();

    for i in items.keys():
        obj.add($i, items[i].itemToJson())

    let tempStorageFile = getTempFile("archive")
    writeFile(tempStorageFile, pretty(obj, 4))
    discard tryRemoveFile(archiveFile)
    moveFile(tempStorageFile, archiveFile)
