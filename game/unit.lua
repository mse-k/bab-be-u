function thiccBlock(undoing)
  --to save headaches, thicc status can only update when a unit is created (or undestroyed) or at this very point)
  local current_thicc = getUnitsWithEffect("thicc");
  local new_thicc_cache = {}
  local any_new = false;
  local current_thicc_cache = {}
  local un_thicc_cache = {}
  local any_un = false;
  for _,unit in ipairs(current_thicc) do
    current_thicc_cache[unit] = true;
    if (not thicc_units[unit]) then
      new_thicc_cache[unit] = true;
      any_new = true;
    end
  end
  
  for unit,_ in pairs(thicc_units) do
    if (not current_thicc_cache[unit]) then
      un_thicc_cache[unit] = true;
      any_un = true;
    end
  end
  
  if (any_new) then
    if (not undoing) then
      playSound("thicc");
    end
    for unit,_ in pairs(new_thicc_cache) do
      if not unit.removed_final then
        if (#undo_buffer == 0) then
          unit.draw.thicc = 2
        else
          unit.draw.thicc = 1
          addTween(tween.new(0.35, unit.draw, {thicc = 2}), "unit:thicc:" .. unit.tempid)
        end
        for i=1,3 do
          if not table.has_value(unitsByTile(unit.x+i%2,unit.y+math.floor(i/2)),unit) then
            table.insert(unitsByTile(unit.x+i%2,unit.y+math.floor(i/2)),unit)
          end
        end
      end
    end
  end
  if (any_un) then
    if (not undoing) then
      playSound("unthicc");
    end
    for unit,_ in pairs(un_thicc_cache) do
     if not unit.removed_final then
      unit.draw.thicc = 2
      addTween(tween.new(0.25, unit.draw, {thicc = 1}), "unit:thicc:" .. unit.tempid)
       for i=1,3 do
          if table.has_value(unitsByTile(unit.x+i%2,unit.y+math.floor(i/2)),unit) then
            removeFromTable(unitsByTile(unit.x+i%2,unit.y+math.floor(i/2)),unit)
          end
        end
      end
    end
  end
  thicc_units = current_thicc_cache;
end

function moveBlock()
  --baba order: FOLLOW, BACK, TELE, SHIFT
  --bab order: thicc, look at, undo, visit fren, go, goooo, shy, spin, folo wal, turn cornr
  
  thiccBlock(false)
  
  local isstalk = matchesRule("?", "lookat", "?")
  for _,ruleparent in ipairs(isstalk) do
    local stalkers = findUnitsByName(ruleparent.rule.subject.name)
    local stalkees = copyTable(findUnitsByName(ruleparent.rule.object.name))
    local stalker_conds = ruleparent.rule.subject.conds
    local stalkee_conds = ruleparent.rule.object.conds
    for _,stalker in ipairs(stalkers) do
      table.sort(stalkees, function(a, b) return euclideanDistance(a, stalker) < euclideanDistance(b, stalker) end )
      for _,stalkee in ipairs(stalkees) do
        if testConds(stalker, stalker_conds) and testConds(stalkee, stalkee_conds, stalker) then
          local dist = euclideanDistance(stalker, stalkee)
          local stalk_dir = dist > 0 and dirs8_by_offset[sign(stalkee.x - stalker.x)][sign(stalkee.y - stalker.y)] or stalkee.dir
          if dist > 0 and hasProperty(stalker, "ortho") then
            local use_hori = math.abs(stalkee.x - stalker.x) > math.abs(stalkee.y - stalker.y)
            stalk_dir = dirs8_by_offset[use_hori and sign(stalkee.x - stalker.x) or 0][not use_hori and sign(stalkee.y - stalker.y) or 0]
          end
          addUndo({"update", stalker.id, stalker.x, stalker.y, stalker.dir})
          stalker.olddir = stalker.dir
          updateDir(stalker, stalk_dir)
          break
        end
      end
    end
  end
  
  local isstalknt = matchesRule("?", "lookaway", "?")
  for _,ruleparent in ipairs(isstalknt) do
    local stalkers = findUnitsByName(ruleparent.rule.subject.name)
    local stalkees = copyTable(findUnitsByName(ruleparent.rule.object.name))
    local stalker_conds = ruleparent.rule.subject.conds
    local stalkee_conds = ruleparent.rule.object.conds
    for _,stalker in ipairs(stalkers) do
      if ruleparent.rule.object.name == "themself" then
        addUndo({"update", stalker.id, stalker.x, stalker.y, stalker.dir})
        stalker.olddir = stalker.dir
        updateDir(stalker, (stalker.dir-1+4)%8 + 1)
      else
        table.sort(stalkees, function(a, b) return euclideanDistance(a, stalker) < euclideanDistance(b, stalker) end )
        for _,stalkee in ipairs(stalkees) do
          if testConds(stalker, stalker_conds) and testConds(stalkee, stalkee_conds, stalker) then
            local dist = euclideanDistance(stalker, stalkee)
            local stalk_dir = dist > 0 and dirs8_by_offset[-sign(stalkee.x - stalker.x)][-sign(stalkee.y - stalker.y)] or stalkee.dir
            if dist > 0 and hasProperty(stalker, "ortho") then
              local use_hori = math.abs(stalkee.x - stalker.x) > math.abs(stalkee.y - stalker.y)
              stalk_dir = dirs8_by_offset[use_hori and sign(stalkee.x - stalker.x) or 0][not use_hori and sign(stalkee.y - stalker.y) or 0]
            end
            addUndo({"update", stalker.id, stalker.x, stalker.y, stalker.dir})
            stalker.olddir = stalker.dir
            updateDir(stalker, stalk_dir)
            break
          end
        end
      end
    end
  end
  
  local to_destroy = {}
  local time_destroy = {}
  
  --UNDO logic:
  --the first time something becomes UNDO, we track what turn it became UNDO on.
  --then every turn thereafter until it stops being UNDO, we undo the update (move backwards) and create (destroy units) events of a turn 2 turns further back (+1 so we keep undoing into the past, +1 because the undo_buffer gained a real turn as well!)
  --We have to keep track of the turn we started backing on in the undo buffer, so that if we undo to a past where a unit was UNDO, then we know what turn to pick back up from. We also have to save/restore backer_turn on destroy, so if we undo the unit's destruction it comes back with the right backer_turn.
  --(The cache is not necessary for the logic, it just removes our need to check ALL units to see if they need to be cleaned up.)
  
  local backed_this_turn = {}
  local not_backed_this_turn = {}
  
  local isback = getUnitsWithEffectAndCount("undo")
  if hasProperty(outerlvl, "undo") then
    for _,unit in ipairs(units) do
      if isback[unit] then
        isback[unit] = isback[unit] + 1
      else
        isback[unit] = 1
      end
    end
  end
  for unit,amt in pairs(isback) do
    unit = units_by_id[unit] or cursors_by_id[unit]
    --print("backing 1:", unit.fullname, amt, unit.backer_turn, backers_cache[unit])
    backed_this_turn[unit] = true
    if (unit.backer_turn == nil) then
      addUndo({"backer_turn", unit.id, nil})
      unit.backer_turn = #undo_buffer+(0.5*(amt-1))
      backers_cache[unit] = unit.backer_turn
    end
    --print("backing 2:", unit.fullname, amt, unit.backer_turn, backers_cache[unit])
    doBack(unit.id, 2*(#undo_buffer-unit.backer_turn))
    for i = 2,amt do
      addUndo({"backer_turn", unit.id, unit.backer_turn})
      unit.backer_turn = unit.backer_turn - 0.5
      doBack(unit.id, 2*(#undo_buffer-unit.backer_turn))
    end
  end
  
  for unit,turn in pairs(backers_cache) do
    if turn ~= nil and not backed_this_turn[unit] then
      not_backed_this_turn[unit] = true
    end
  end
  
  for unit,_ in pairs(not_backed_this_turn) do
    addUndo({"backer_turn", unit.id, unit.backer_turn})
    unit.backer_turn = nil
    backers_cache[unit] = nil
  end
  
  to_destroy = handleDels(to_destroy)
  
  --Currently using deterministic tele version. Number of teles a teleporter has influences whether it goes forwards or backwards and by how many steps.
  local istele = getUnitsWithEffectAndCount("visitfren")
  teles_by_name = {}
  teles_by_name_index = {}
  tele_targets = {}
  --form lists, by tele name, of what all the tele units are
  for unit,amt in pairs(istele) do
    unit = units_by_id[unit] or cursors_by_id[unit]
    if teles_by_name[unit.fullname] == nil then
      teles_by_name[unit.fullname] = {}
    end
    table.insert(teles_by_name[unit.fullname], unit)
  end
  --then sort those lists in reading order (tiebreaker is id).
  --skip this step if doing random version, the sorting won't matter then!
  for name,tbl in pairs(teles_by_name) do
    table.sort(tbl, readingOrderSort)
  end
  --form a lookup index for each of those lists
  for name,tbl in pairs(teles_by_name) do
    teles_by_name_index[name] = {}
    for k,v in ipairs(tbl) do
      teles_by_name_index[name][v] = k
    end
  end
  --now do the actual teleports. we can use the index to know our own place in the list so we can skip ourselves
  for unit,amt in pairs(istele) do
    unit = units_by_id[unit] or cursors_by_id[unit]
    local stuff = getUnitsOnTile(unit.x, unit.y, {not_destroyed = true, thicc = thicc_units[unit]})
    for _,on in ipairs(stuff) do
      --we're going to deliberately let two same name teles tele if they're on each other, since with the deterministic behaviour it's predictable and interesting
      if unit ~= on and sameFloat(unit, on) and ignoreCheck(unit, on, "visitfren") and timecheck(unit,"be","visitfren") --[[and unit.fullname ~= on.fullname]] then
        local destinations = teles_by_name[unit.fullname]
        local source_index = teles_by_name_index[unit.fullname][unit]
        
        --RANDOM VERSION: just pick any tele that isn't us
        --[[local dest = math.floor(math.random()*(#destinations-1))+1 --even distribution of each integer. +1 because lua is 1 indexed, -1 because we want one less than the number of teleporters (since we're going to ignore our own)
        if (dest >= source_index) then
          dest = dest + 1
        end]]
        
        --DETERMINISTIC VERSION: 1/-1/2/-2/3/-3... based on amount of TELE, in reading order.
        local dest = source_index + (math.floor(amt/2+0.5) * (amt % 2 == 1 and 1 or -1))
        --have to subtract 1/add 1 because arrays are 1 indexed but modulo arithmetic is 0 indexed.
        dest = ((dest-1) % (#destinations))+1
        if dest == source_index then
          dest = dest + 1
        end
        dest = ((dest-1) % (#destinations))+1
        tele_targets[on] = destinations[dest]
      end
    end
  end
  for a,b in pairs(tele_targets) do
    addUndo({"update", a.id, a.x, a.y, a.dir})
    moveUnit(a, b.x, b.y)
  end
  
  local ishere, hererules = getUnitsWithEffect("her", true)
  local hashered = {}
  for ri,unit in ipairs(ishere) do
    --checks to see if the unit has already been moved by "her"
    local already = false
    for _,moved in ipairs(hashered) do
      if unit == moved then
        already = true
      end
    end
    
    --if it has, then don't run code this iteration
    if not already then
      local heres = {}
      local found = false
      
      --gets each destination the unit needs to go to
      local fullrule = hererules[ri].units
      for i,hererule in ipairs(fullrule) do
        if hererule.fullname == "txt_her" then
          table.insert(heres,hererule)
          break
        end
      end
      --sorts it like "visitfren"
      for name,tbl in pairs(heres) do
        table.sort(tbl, readingOrderSort)
      end
      
      --actual teleport
      for i,here in ipairs(heres) do
        local dx = dirs8[here.dir][1]
        local dy = dirs8[here.dir][2]
        
        --if this is true, it means that on the last iteration it found a unit at a destination, so on this iteration it teleports it to the following one
        if found then
          addUndo({"update", unit.id, unit.x, unit.y, unit.dir})
          moveUnit(unit,here.x+dx,here.y+dy)
          table.insert(hashered,unit)
          break
        end
        
        --if i == #heres, that means it's at the last one in line, meaning we can just use the system that sends it to the first word
        --otherwise, if it finds unit at one of the places, that means that it should send it to the next one on the next turn
        if (unit.x == here.x+dx) and (unit.y == here.y+dy) and (i ~= #heres) then
          found = true
        end
      end
      
      --sends it to the first "here" if it isn't at any existing destination or if it's at the last
      if not found then
        local firsthere = heres[1]
        local dx = dirs8[firsthere.dir][1]
        local dy = dirs8[firsthere.dir][2]
        
        addUndo({"update", unit.id, unit.x, unit.y, unit.dir})
        moveUnit(unit,firsthere.x+dx,firsthere.y+dy)
        table.insert(hashered,unit)
      end
    end
  end
  
  local isthere, thererules = getUnitsWithEffect("thr", true)
  local hasthered = {}
  for ri,unit in ipairs(isthere) do
    --the early stuff is the same as "her"; finds "thr"s and sort them
    local dontmove = false
    for _,moved in ipairs(hasthered) do
      if unit == moved then
        dontmove = true
      end
    end
    
    if not dontmove then
      local theres = {}
      local found = false
      
      local fullrule = thererules[ri].units
      for i,thererule in ipairs(fullrule) do
        if thererule.fullname == "txt_thr" then
          table.insert(theres,thererule)
          break
        end
      end

      for name,tbl in pairs(theres) do
        table.sort(tbl, readingOrderSort)
      end
      
      --starts differing from "her"
      local ftx,fty = 0,0
      for i,there in ipairs(theres) do
        local dx = dirs8[there.dir][1]
        local dy = dirs8[there.dir][2]
        local dir = there.dir
        
        --get first position of there destination, which is the tile the text is on, so we can check whether the first space is valid
        local tx = there.x
        local ty = there.y
        
        --code has gotten more complicated now, more comments added
        local stopped = false
        local valid = false
        local loopstage = 0
        while not stopped do
          local canmove = canMove(unit,dx,dy,dir,{start_x = tx, start_y = ty, ignorestukc = true}) --simplify since we check this more often now
          
          --while valid is false, it check this. this makes it so it's false until you get out of the stops, or always true if there wasn't a stop at first
          if not valid then
            valid = canmove
          else --if it's found a valid space to be in, start checking to see when it gets stopped by a wall
            stopped = not canmove
          end
          
          if not stopped then --as long as it hasn't found a valid place to stop at, check the next tile
            dx,dy,dir,tx,ty = getNextTile(there, dx, dy, dir, nil, tx, ty)
          end
          
          --infinite check
          loopstage = loopstage + 1
          if loopstage > 1000 then
            if valid then --if the unit has found a valid space to be, that means it's stuck in a loop of valid places, so it should infloop
              print("movement infinite loop! (1000 attempts at thr)")
              destroyLevel("infloop")
            else --if the unit hasn't found a valid space, that means it's stuck in walls, meaning it never has the opportunity to be moved
              dontmove = true
            end
            break
          end
        end
        
        --stores the first destination for use later so we don't have to run the while loop twice
        if i == 1 then
          ftx,fty = tx,ty
        end
        
        if found then
          addUndo({"update", unit.id, unit.x, unit.y, unit.dir})
          moveUnit(unit,tx,ty)
          table.insert(hasthered,unit)
        end
        
        if (unit.x == tx) and (unit.y == ty) and (i ~= #theres) then
          found = true
        end
      end
      
      if not found and not dontmove then
        addUndo({"update", unit.id, unit.x, unit.y, unit.dir})
        moveUnit(unit,ftx,fty)
        table.insert(hasthered,unit)
      end
    end
  end
  
  local isrighthere, righthererules = getUnitsWithEffect("rithere", true)
  local hasrighthered = {}
  for ri,unit in ipairs(isrighthere) do
    local already = false
    for _,moved in ipairs(hasrighthered) do
      if unit == moved then
        already = true
      end
    end
    
    if not already then
      local rightheres = {}
      local found = false
      
      local fullrule = righthererules[ri].units
      for i,righthererule in ipairs(fullrule) do
        if righthererule.fullname == "txt_rithere" then
          table.insert(rightheres,righthererule)
          break
        end
      end
      
      for name,tbl in pairs(rightheres) do
        table.sort(tbl, readingOrderSort)
      end
      
      for i,righthere in ipairs(rightheres) do
        if found then
          addUndo({"update", unit.id, unit.x, unit.y, unit.dir})
          moveUnit(unit,righthere.x,righthere.y)
          table.insert(hasrighthered,unit)
          break
        end
        if (unit.x == righthere.x) and (unit.y == righthere.y) and (i ~= #rightheres) then
          found = true
        end
      end
      
      if not found then
        local firstrighthere = rightheres[1]
        addUndo({"update", unit.id, unit.x, unit.y, unit.dir})
        moveUnit(unit,firstrighthere.x,firstrighthere.y)
        table.insert(hasrighthered,unit)
      end
    end
  end
  
  --Use a similar simultaneous/additive algorithm to copkat/go^.
  
  units_to_change = {}
  
  
  local isshift = getUnitsWithEffect("go")
  for _,unit in ipairs(isshift) do
    local stuff = getUnitsOnTile(unit.x, unit.y, {not_destroyed = true, thicc = thicc_units[unit]})
    for _,on in ipairs(stuff) do
      if unit ~= on and sameFloat(unit, on) and ignoreCheck(unit, on, "go") and timecheck(unit,"be","go") then
        if (units_to_change[on] == nil) then
          units_to_change[on] = {0, 0}
        end
        units_to_change[on][1] = units_to_change[on][1] + dirs8[unit.dir][1]
        units_to_change[on][2] = units_to_change[on][2] + dirs8[unit.dir][2]
      end
    end
  end
  
  local isshift = getUnitsWithEffect("goooo")
  for _,unit in ipairs(isshift) do
    local stuff = getUnitsOnTile(unit.x, unit.y, {not_destroyed = true, thicc = thicc_units[unit]})
    for _,on in ipairs(stuff) do
      if unit ~= on and sameFloat(unit, on) and ignoreCheck(unit, on, "goooo") and timecheck(unit,"be","goooo") then
         if (units_to_change[on] == nil) then
          units_to_change[on] = {0, 0}
        end
        units_to_change[on][1] = units_to_change[on][1] + dirs8[unit.dir][1]
        units_to_change[on][2] = units_to_change[on][2] + dirs8[unit.dir][2]
      end
    end
  end
  
  for unit,dir in pairs(units_to_change) do
    if dir[1] ~= 0 or dir[2] ~= 0 then
      k = dirs8_by_offset[sign(dir[1])][sign(dir[2])]
      if unit.dir ~= k then
        addUndo({"update", unit.id, unit.x, unit.y, unit.dir})
      end
      updateDir(unit, k)
    end
  end
  
  local isshy = getUnitsWithEffect("shy...")
  for _,unit in ipairs(isshy) do
    if not hasProperty("folowal") and not hasProperty("turncornr") then
      local dpos = dirs8[unit.dir]
      local dx, dy = dpos[1], dpos[2]
      local stuff = getUnitsOnTile(unit.x+dx, unit.y+dy, {not_destroyed = true, thicc = thicc_units[unit]})
      local stuff2 = getUnitsOnTile(unit.x-dx, unit.y-dy, {not_destroyed = true, thicc = thicc_units[unit]})
      local pushfront = false
      local pushbehin = false
      for _,on in ipairs(stuff) do
        if hasProperty(on, "goawaypls") and ignoreCheck(unit, on, "goawaypls") then
          pushfront = true
          break
        end
      end
      if pushfront then
        for _,on in ipairs(stuff2) do
          if hasProperty(on, "goawaypls") and ignoreCheck(unit, on, "goawaypls") then
            pushbehin = true
            break
          end
        end
      end
      if pushfront and not pushbehin then
        addUndo({"update", unit.id, unit.x, unit.y, unit.dir})
        updateDir(unit, rotate8(unit.dir))
      end
    end
  end
  
  doSpinRules()
  
  local folo_wall = getUnitsWithEffectAndCount("folowal")
  for unit,amt in pairs(folo_wall) do
    unit = units_by_id[unit] or cursors_by_id[unit]
    local fwd = unit.dir
    local right = (((unit.dir + 2)-1)%8)+1
    local bwd = (((unit.dir + 4)-1)%8)+1
    local left = (((unit.dir + 6)-1)%8)+1
    local result = changeDirIfFree(unit, right) or changeDirIfFree(unit, fwd) or changeDirIfFree(unit, left) or changeDirIfFree(unit, bwd)
  end
  
  local turn_cornr = getUnitsWithEffectAndCount("turncornr")
  for unit,amt in pairs(turn_cornr) do
    unit = units_by_id[unit] or cursors_by_id[unit]
    local fwd = unit.dir
    local right = (((unit.dir + 2)-1)%8)+1
    local bwd = (((unit.dir + 4)-1)%8)+1
    local left = (((unit.dir + 6)-1)%8)+1
    local result = changeDirIfFree(unit, fwd) or changeDirIfFree(unit, right) or changeDirIfFree(unit, left) or changeDirIfFree(unit, bwd)
  end
end

function updateUnits(undoing, big_update)
  max_layer = 1
  units_by_layer = {}
  local del_units = {}
  local will_undo = false
  
  deleteUnits(del_units,false)
  
  --handle non-monotonic (creative, destructive) effects one at a time, so that we can process them in a set order instead of unit order
  --BABA order is as follows: DONE, BLUE, RED, MORE, SINK, WEAK, MELT, DEFEAT, SHUT, EAT, BONUS, END, WIN, MAKE, HIDE
  --(FOLLOW, BACK, TELE, SHIFT are handled in moveblock. FALL is handled in fallblock.)

  if (big_update and not undoing) then
    if not hasProperty(nil,"zawarudo") then
      timeless = false
    end
    
    if not timeless then
      time_destroy = handleTimeDels(time_destroy)
    end
    
    local wins,unwins = levelBlock()
    
    
    local isgone = getUnitsWithEffect("gone")
    for _,unit in ipairs(isgone) do
      unit.destroyed = true
      unit.removed = true
    end
    deleteUnits(isgone, false, true)
    
    --moar remake: based on the scent map distance in brogue (thanks notnat/pata for inspiration)
    local already_grown = {}
    local pending_growth = {}
    local pending_gone = {}
    local moars = getUnitsWithEffectAndCountAndAnti("moar")
    for unit,aamt in pairs(moars) do
      unit = units_by_id[unit] or cursors_by_id[unit]
      local amt = math.abs(aamt)
      if (unit.name ~= "lie/8" or hasProperty(unit,"notranform")) and timecheck(unit,"be","moar") then
        local range = math.ceil(amt/2)
        for y_=-range,range do
          local y = y_
          local absy = math.abs(y)
          for x_=-range,range do
            local x = x_
            local absx = math.abs(x)
            if (absx+absy+math.max(absx,absy)-1 <= amt) and (x ~= 0 or y ~= 0) then --this line handles the area thing. 0,0 checking is because it's weird without it
              if thicc_units[unit] then
                x = x*2
                y = y*2
              end
              if aamt > 0 then
                already_grown[getUnitStr(unit)] = already_grown[getUnitStr(unit)] or {}
                if canMove(unit, x, y, unit.dir) then
                  if unit.class == "unit" then --idk what any of this means but i'm assuming it's good?
                    _, __, ___, mx, my = getNextTile(unit, x, y, i*2-1, false)
                    if not already_grown[getUnitStr(unit)][mx..","..my] then
                      local blocked = false
                      local others = getUnitsOnTile(mx, my, {name = unit.fullname})
                      for _,other in ipairs(others) do
                        if getUnitStr(other) == getUnitStr(unit) then
                          blocked = true
                        end
                      end
                      if not blocked then
                        table.insert(pending_growth, {unit, mx, my})
                      end
                      already_grown[getUnitStr(unit)][mx..","..my] = true
                    end
                  elseif unit.class == "cursor" then
                    local others = getCursorsOnTile(unit.x + x, unit.y + y)
                    if #others == 0 and not already_grown[getUnitStr(unit)][(unit.x+x)..","..(unit.y+y)] then
                      table.insert(pending_growth, {unit, unit.x + x, unit.y + y})
                      already_grown[getUnitStr(unit)][(unit.x+x)..","..(unit.y+y)] = true
                    end
                  end
                end
              else
                if canMove(unit, x, y, unit.dir) then
                  _, __, ___, mx, my = getNextTile(unit, x, y, i*2-1, false)
                  local others = getUnitsOnTile(mx, my, {name = unit.fullname})
                  local matched = false
                  for _,other in ipairs(others) do
                    if getUnitStr(other) == getUnitStr(unit) then
                      matched = true
                      break
                    end
                  end
                  if not matched then 
                    table.insert(pending_gone, unit)
                    goto continue
                  end
                end
              end
            end
          end --x for
        end
      end
      ::continue::
    end
    for _,growing in ipairs(pending_growth) do
      local unit, x, y = unpack(growing)
      if unit.class == "unit" then
        local color
        if unit.color_override then
          color = colour_for_palette[getUnitColor(unit)[1]][getUnitColor(unit)[2]]
        end
        local new_unit = createUnit(unit.tile, unit.x, unit.y, unit.dir, nil, nil, nil, color)
        addUndo({"create", new_unit.id, false})
        moveUnit(new_unit,x,y)
        addUndo({"update", new_unit.id, unit.x, unit.y, unit.dir})
      elseif unit.class == "cursor" then
        local new_mouse = createMouse(x, y)
        addUndo({"create_cursor", new_mouse.id})
      end
    end
    for _,unit in ipairs(pending_gone) do
      unit.destroyed = true
      unit.removed = true
    end
    deleteUnits(pending_gone, true)
    
    local to_destroy = {}
    if time_destroy == nil then
      time_destroy = {}
    end
    
    local nukes = getUnitsWithEffect("nuek")
    local fires = copyTable(findUnitsByName("xplod"))
    if #nukes > 0 then
      for _,nuke in ipairs(nukes) do
        local check = getUnitsOnTile(nuke.x,nuke.y,{thicc = thicc_units[unit]})
        local lit = false
        for _,other in ipairs(check) do
          if other.name == "xplod" then
            lit = true
          end
        end
        if not lit then
          local new_unit = createUnit("xplod", nuke.x, nuke.y, nuke.dir)
          addUndo({"create", new_unit.id, false})
          if hasProperty(nuke,"thicc") then
            for i=1,3 do
              local _new_unit = createUnit("xplod", nuke.x+i%2, nuke.y+math.floor(i/2), nuke.dir)
              addUndo({"create", _new_unit.id, false})
            end
          end
          for _,other in ipairs(check) do
            if other ~= nuke and ignoreCheck(other, nuke, "nuek") then
              table.insert(to_destroy,other)
              playSound("break")
              addParticles("destroy", other.x, other.y, {2,2})
            end
          end
        end
      end
      for _,fire in ipairs(fires) do
        if inBounds(fire.x,fire.y) then
          for i=1,7,2 do
            local dx = dirs8[i][1]
            local dy = dirs8[i][2]
            local lit = false
            local others = getUnitsOnTile(fire.x+dx,fire.y+dy)
            if inBounds(fire.x+dx,fire.y+dy) then
              for _,on in ipairs(others) do
                if ignoreCheck(on, nil, "nuek") then
                  if on.name == "xplod" or hasProperty(on, "nuek") or hasProperty(on, "protecc") then
                    lit = true
                  else
                    table.insert(to_destroy,on)
                    playSound("break")
                    addParticles("destroy", on.x, on.y, {2,2})
                  end
                end
              end
              if not lit then
                local new_unit = createUnit("xplod", fire.x+dx, fire.y+dy, 1)
                addUndo({"create", new_unit.id, false})
              end
            end
          end
        else
          table.insert(to_destroy,fire)
        end
      end
    else
      for _,fire in ipairs(fires) do
        table.insert(to_destroy,fire)
      end
    end
    
    to_destroy = handleDels(to_destroy)
    
    local split_movers = {}
    if not timeless then
      for on,unit in pairs(timeless_split) do
        addUndo({"timeless_split_remove", on, unit})
        unit = units_by_id[unit] or cursors_by_id[unit]
        on = units_by_id[on]
        if (unit ~= nil and on ~= nil) then
          table.insert(to_destroy, on)
          local dir1 = dirAdd(unit.dir,0)
          local dx1 = dirs8[dir1][1]
          local dy1 = dirs8[dir1][2]
          local dir2 = dirAdd(unit.dir,4)
          local dx2 = dirs8[dir2][1]
          local dy2 = dirs8[dir2][2]
          if canMove(on, dx1, dy1, dir1) then
            if on.class == "unit" then
              local new_unit = createUnit(on.tile, on.x, on.y, dir1)
              addUndo({"create", new_unit.id, false})
              _, __, ___, x, y = getNextTile(on, dx1, dy1, dir1, false)
              table.insert(split_movers,{unit = new_unit, x = x, y = y, ox = on.x, oy = on.y, dir = dir1})
            elseif unit.class == "cursor" then
              local others = getCursorsOnTile(on.x + dx1, on.y + dy1)
              if #others == 0 then
                local new_mouse = createMouse(on.x + dx1, on.y + dy1)
                addUndo({"create_cursor", new_mouse.id})
              end
            end
          end
          if canMove(on, dx2, dy2, dir2) then
            if on.class == "unit" then
              local new_unit = createUnit(on.tile, on.x, on.y, dir2)
              addUndo({"create", new_unit.id, false})
              _, __, ___, x, y = getNextTile(on, dx2, dy2, dir2, false)
              table.insert(split_movers,{unit = new_unit, x = x, y = y, ox = on.x, oy = on.y, dir = dir2})
            elseif unit.class == "cursor" then
              local others = getCursorsOnTile(on.x + dx2, on.y + dy2)
              if #others == 0 then
                local new_mouse = createMouse(on.x + dx2, on.y + dy2)
                addUndo({"create_cursor", new_mouse.id})
              end
            end
          end
        end
      end
      timeless_split = {}
    end
    
    --an attempt to prevent stacking split from crashing by limiting how many splits we try to do per tile. it's OK, it leads to weird traffic jams though because the rest of the units just stay still.
    local splits_per_tile = {}
    local split = getUnitsWithEffect("split")
    for _,unit in ipairs(split) do
      if (unit.name ~= "lie" or hasProperty(unit,"notranform")) then
        local coords = tostring(unit.x)..","..tostring(unit.y)
        if (splits_per_tile[coords]) == nil then
          splits_per_tile[coords] = 0
        end
        if splits_per_tile[coords] < 16 then
          local stuff = getUnitsOnTile(unit.x, unit.y, {not_destroyed = true, thicc = thicc_units[unit]})
          for _,on in ipairs(stuff) do
            if splits_per_tile[coords] >= 16 then break end
            if unit ~= on and sameFloat(unit, on) and not on.new and ignoreCheck(on, unit, "split") then
              if timecheck(unit,"be","split") and timecheck(on) then
                local dir1 = dirAdd(unit.dir,0)
                local dx1 = dirs8[dir1][1]
                local dy1 = dirs8[dir1][2]
                local dir2 = dirAdd(unit.dir,4)
                local dx2 = dirs8[dir2][1]
                local dy2 = dirs8[dir2][2]
                if canMove(on, dx1, dy1, dir1) then
                  if on.class == "unit" then
                    splits_per_tile[coords] = splits_per_tile[coords] + 1
                    local new_unit = createUnit(on.tile, on.x, on.y, dir1)
                    addUndo({"create", new_unit.id, false})
                    _, __, ___, x, y = getNextTile(on, dx1, dy1, dir1, false)
                    table.insert(split_movers,{unit = new_unit, x = x, y = y, ox = on.x, oy = on.y, dir = dir1})
                  elseif unit.class == "cursor" then
                    local others = getCursorsOnTile(on.x + dx1, on.y + dy1)
                    if #others == 0 then
                      local new_mouse = createMouse(on.x + dx1, on.y + dy1)
                      addUndo({"create_cursor", new_mouse.id})
                    end
                  end
                end
                if canMove(on, dx2, dy2, dir2) then
                  if on.class == "unit" then
                    splits_per_tile[coords] = splits_per_tile[coords] + 1
                    local new_unit = createUnit(on.tile, on.x, on.y, dir2)
                    addUndo({"create", new_unit.id, false})
                    _, __, ___, x, y = getNextTile(on, dx2, dy2, dir2, false)
                    table.insert(split_movers,{unit = new_unit, x = x, y = y, ox = on.x, oy = on.y, dir = dir2})
                  elseif unit.class == "cursor" then
                    local others = getCursorsOnTile(on.x + dx2, on.y + dy2)
                    if #others == 0 then
                      local new_mouse = createMouse(on.x + dx2, on.y + dy2)
                      addUndo({"create_cursor", new_mouse.id})
                    end
                  end
                end
                table.insert(to_destroy, on)
              else
                if not timeless_split[on.id] then
                  addUndo({"timeless_split_add", on.id})
                  timeless_split[on.id] = unit.id
                  addParticles("destroy", unit.x, unit.y, getUnitColor(unit))
                end
              end
            end
          end
        end
      else
        if timecheck(unit,"be","split") then
          for i=1,8 do
            local ndir = dirs8[i]
            local dx = ndir[1]
            local dy = ndir[2]
            if canMove(unit, dx, dy, i) then
              local new_unit = createUnit("lie/8", unit.x, unit.y, i)
              addUndo({"create", new_unit.id, false})
              _, __, ___, x, y = getNextTile(unit, dx, dy, i, false)
              moveUnit(new_unit,x,y)
              addUndo({"update", new_unit.id, unit.x, unit.y, unit.dir})
            end
          end
          table.insert(to_destroy, unit)
        end
      end
    end
    
    for _,move in ipairs(split_movers) do
      moveUnit(move.unit,move.x,move.y)
      addUndo({"update", move.unit.id, move.ox, move.oy, move.dir})
    end
    
    to_destroy = handleDels(to_destroy)
    
    local isvs = matchesRule(nil,"vs","?")
    for _,ruleparent in ipairs(isvs) do
      local unit = ruleparent[2]
      local stuff = getUnitsOnTile(unit.x, unit.y, {not_destroyed = true, checkmous = true, thicc = thicc_units[unit]})
      for _,on in ipairs(stuff) do
        if (unit ~= on or ruleparent[1].rule.object.name == "themself") and hasRule(unit, "vs", on) and sameFloat(unit, on) then
          local unitmoved = false
          local onmoved = false
          for _,undo in ipairs(undo_buffer[1]) do
            if undo[1] == "update" and undo[2] == unit.id and ((undo[3] ~= unit.x) or (undo[4] ~= unit.y)) then
              unitmoved = true
            end
            if undo[1] == "update" and undo[2] == on.id and ((undo[3] ~= on.x) or (undo[4] ~= on.y)) then
              onmoved = true
            end
          end
          if unitmoved and ignoreCheck(on, unit) then
            if timecheck(unit,"vs",on) then
              table.insert(to_destroy,on)
              playSound("break")
            else
              table.insert(time_destroy,{on.id,timeless})
              addUndo({"time_destroy",on.id})
            end
            addParticles("destroy", on.x, on.y, getUnitColor(on))
          end
          if onmoved and ignoreCheck(unit, on) then
            if timecheck(unit,"vs",on) then
              table.insert(to_destroy,unit)
              playSound("break")
            else
              table.insert(time_destroy,{unit.id,timeless})
              addUndo({"time_destroy",unit.id})
            end
            addParticles("destroy", unit.x, unit.y, getUnitColor(unit))
          end
        end
      end
    end
    
    to_destroy = handleDels(to_destroy)
    
    local issink = getUnitsWithEffect("noswim")
    for _,unit in ipairs(issink) do
      local stuff = getUnitsOnTile(unit.x, unit.y, {not_destroyed = true, thicc = thicc_units[unit]})
      for _,on in ipairs(stuff) do
        if unit ~= on and on.fullname ~= "no1" and sameFloat(unit, on) then
          local ignore_unit = ignoreCheck(unit, on)
          local ignore_on = ignoreCheck(on, unit, "noswim")
          if ignore_unit or ignore_on then
            if timecheck(unit,"be","noswim") and timecheck(on) then
              if ignore_unit then
                table.insert(to_destroy, unit)
              end
              if ignore_on then
                table.insert(to_destroy, on)
              end
              playSound("sink")
              shakeScreen(0.3, 0.1)
            else
              if ignore_unit then
                table.insert(time_destroy,{unit.id,timeless})
                addUndo({"time_destroy",unit.id})
              end
              if ignore_on then
                table.insert(time_destroy,{on.id,timeless})
                addUndo({"time_destroy",on.id})
              end
              table.insert(time_sfx,"sink")
            end
            if ignore_unit then
              addParticles("destroy", unit.x, unit.y, ignore_on and getUnitColor(on) or getUnitColor(unit))
            else
              addParticles("destroy", on.x, on.y, getUnitColor(on))
            end
          end
        end
      end
    end
    
    to_destroy = handleDels(to_destroy)
    
    local isweak = getUnitsWithEffect("ouch")
    for _,unit in ipairs(isweak) do
      local stuff = getUnitsOnTile(unit.x, unit.y, {not_destroyed = true, thicc = thicc_units[unit]})
      for _,on in ipairs(stuff) do
        if unit ~= on and sameFloat(unit, on) and ignoreCheck(unit, on) then
          if timecheck(unit,"be","ouch") and timecheck(on) then
            table.insert(to_destroy, unit)
            playSound("break")
            shakeScreen(0.3, 0.1)
          else
            table.insert(time_destroy,{unit.id,timeless})
						addUndo({"time_destroy",unit.id})
            table.insert(time_sfx,"break")
          end
          addParticles("destroy", unit.x, unit.y, getUnitColor(unit))
        end
      end
    end
    
    to_destroy = handleDels(to_destroy)
    
    local isstrong = getUnitsWithEffect("anti ouch")
    for _,unit in ipairs(isstrong) do
      local stuff = getUnitsOnTile(unit.x, unit.y, {not_destroyed = true, thicc = thicc_units[unit]})
      for _,on in ipairs(stuff) do
        if on ~= unit and sameFloat(on, unit) and ignoreCheck(on, unit) then
          if timecheck(unit,"be","anti ouch") and timecheck(on) then
            table.insert(to_destroy, on)
            playSound("break")
            shakeScreen(0.3, 0.1)
          else
            table.insert(time_destroy,{on.id,timeless})
						addUndo({"time_destroy",on.id})
            table.insert(time_sfx,"break")
          end
          addParticles("destroy", on.x, on.y, getUnitColor(on))
        end
      end
    end
    
    to_destroy = handleDels(to_destroy)
    
    local ishot = getUnitsWithEffect("hotte")
    for _,unit in ipairs(ishot) do
      local stuff = getUnitsOnTile(unit.x, unit.y, {not_destroyed = true, checkmous = true, thicc = thicc_units[unit]})
      for _,on in ipairs(stuff) do
        if hasProperty(on, "fridgd") and sameFloat(unit, on) and ignoreCheck(on, unit, "hotte") then
          if timecheck(unit,"be","hotte") and timecheck(on,"be","fridgd") then
            table.insert(to_destroy, on)
            playSound("hotte")
            shakeScreen(0.3, 0.1)
          else
            table.insert(time_destroy,{on.id,timeless})
						addUndo({"time_destroy",on.id})
            table.insert(time_sfx,"hotte")
          end
          addParticles("destroy", unit.x, unit.y, getUnitColor(unit))
        end
      end
    end
    
    to_destroy = handleDels(to_destroy)
    
    local isdefeat = getUnitsWithEffect(":(")
    for _,unit in ipairs(isdefeat) do
      local stuff = getUnitsOnTile(unit.x, unit.y, {not_destroyed = true, checkmous = true, thicc = thicc_units[unit]})
      for _,on in ipairs(stuff) do
        if hasU(on) and sameFloat(unit, on) and ignoreCheck(on, unit, ":(") then
          if timecheck(unit,"be",":(") and (timecheckUs(on)) then
            table.insert(to_destroy, on)
            playSound("break")
            shakeScreen(0.3, 0.2)
          else
            table.insert(time_destroy,{on.id,timeless})
						addUndo({"time_destroy",on.id})
            table.insert(time_sfx,"break")
          end
          addParticles("destroy", unit.x, unit.y, getUnitColor(unit))
        end
      end
    end
    
    to_destroy = handleDels(to_destroy)
    
    local isantidefeat = getUnitsWithEffect("anti :(")
    for _,unit in ipairs(isantidefeat) do
      local stuff = getUnitsOnTile(unit.x, unit.y, {not_destroyed = true, checkmous = true, thicc = thicc_units[unit]})
      for _,on in ipairs(stuff) do
        if hasU(on) and sameFloat(unit, on) and ignoreCheck(on, unit, ":(") then
          if timecheck(unit,"be","anti :(") and (timecheckUs(on)) then
            table.insert(to_destroy, unit)
            playSound("break")
            shakeScreen(0.3, 0.2)
          else
            table.insert(time_destroy,{unit.id,timeless})
						addUndo({"time_destroy",unit.id})
            table.insert(time_sfx,"break")
          end
          addParticles("destroy", unit.x, unit.y, getUnitColor(on))
        end
      end
    end
    
    to_destroy = handleDels(to_destroy)
    
    local isntprotecc = getUnitsWithEffect("anti protecc")
    for _,unit in ipairs(isntprotecc) do
      if timecheck(unit,"be","anti protecc") then
        table.insert(to_destroy, unit)
        playSound("break")
      else
        table.insert(time_destroy,{unit.id,timeless})
        addUndo({"time_destroy",unit.id})
        table.insert(time_sfx,"break")
      end
      addParticles("destroy", unit.x, unit.y, getUnitColor(unit))
    end
    
    to_destroy = handleDels(to_destroy)
    
    local isshut = getUnitsWithEffect("nedkee")
    for _,unit in ipairs(isshut) do
      local stuff = getUnitsOnTile(unit.x, unit.y, {not_destroyed = true, checkmous = true, thicc = thicc_units[unit]})
      for _,on in ipairs(stuff) do
        if hasProperty(on, "fordor") and sameFloat(unit, on) then
          local ignore_unit = ignoreCheck(unit, on, "fordor")
          local ignore_on = ignoreCheck(on, unit, "nedkee")
          if ignore_unit or ignore_on then
            if timecheck(unit,"be","nedkee") and timecheck(on,"be","fordor") then
              if ignore_unit then
                table.insert(to_destroy, unit)
              end
              if ignore_on then
                table.insert(to_destroy, on)
              end
              playSound("break")
              playSound("unlock")
              shakeScreen(0.3, 0.1)
            else
              if ignore_unit then
                table.insert(time_destroy,{unit.id,timeless})
                addUndo({"time_destroy",unit.id})
              end
              if ignore_on then
                table.insert(time_destroy,{on.id,timeless})
                addUndo({"time_destroy",on.id})
              end
              table.insert(time_sfx,"break")
              table.insert(time_sfx,"unlock")
            end
            if ignore_unit then
              addParticles("destroy", unit.x, unit.y, getUnitColor(unit))
            end
            if ignore_on then
              addParticles("destroy", on.x, on.y, getUnitColor(on))
            end
            --unlike other destruction effects, keys and doors pair off one-by-one
            to_destroy = handleDels(to_destroy)
            break
          end
        end
      end
    end
    
    local issnacc = matchesRule(nil, "snacc", "?")
    for _,ruleparent in ipairs(issnacc) do
      local unit = ruleparent[2]
      local stuff = getUnitsOnTile(unit.x, unit.y, {not_destroyed = true, checkmous = true, thicc = thicc_units[unit]})
      for _,on in ipairs(stuff) do
        if (unit ~= on or ruleparent[1].rule.object.name == "themself") and hasRule(unit, "snacc", on) and sameFloat(unit, on) and ignoreCheck(on, unit) then
          if not hasProperty(unit, "anti lesbad") and not hasProperty(on, "anti lesbad") then
            if timecheck(unit,"snacc",on) and timecheck(on) then
              table.insert(to_destroy, on)
              playSound("snacc")
              shakeScreen(0.3, 0.15)
            else
              table.insert(time_destroy,{on.id,timeless})
              addUndo({"time_destroy",on.id})
              table.insert(time_sfx,"snacc")
            end
            addParticles("destroy", unit.x, unit.y, getUnitColor(unit))
          end
        end
      end
    end
    
    to_destroy = handleDels(to_destroy)
    
    local isreset = getUnitsWithEffect("tryagain")
    for _,unit in ipairs(isreset) do
      local stuff = getUnitsOnTile(unit.x, unit.y, {not_destroyed = true, checkmous = true, thicc = thicc_units[unit]})
      for _,on in ipairs(stuff) do
        if hasU(on) and sameFloat(unit, on) and ignoreCheck(on, unit, "tryagain") then
          if timecheck(unit,"be","tryagain") and (timecheckUs(on)) then
            will_undo = true
            break
          else
            addUndo({"timeless_reset_add"})
            timeless_reset = true
            addParticles("bonus", unit.x, unit.y, getUnitColor(unit))
          end
        end
      end
    end
    
    local isreplay = getUnitsWithEffect("anti tryagain")
    for _,unit in ipairs(isreplay) do
      local stuff = getUnitsOnTile(unit.x, unit.y, {not_destroyed = true, checkmous = true, thicc = thicc_units[unit]})
      for _,on in ipairs(stuff) do
        if hasU(on) and sameFloat(unit, on) and ignoreCheck(on, unit, "tryagain") then
          if timecheck(unit,"be","anti tryagain") and (timecheckUs(on)) then
            tryStartReplay(true)
          else
            addUndo({"timeless_replay_add"})
            timeless_replay = true
            addParticles("bonus", unit.x, unit.y, getUnitColor(unit))
          end
        end
      end
    end
    
    local iscrash = matchesRule(nil,"be","delet")
    for _,ruleparent in ipairs(iscrash) do
      local unit = ruleparent[2]
      if not hasProperty(ruleparent[1].rule.object,"slep") then
        local stuff = getUnitsOnTile(unit.x, unit.y, {not_destroyed = true, checkmous = true, thicc = thicc_units[unit]})
        for _,on in ipairs(stuff) do
          if hasU(on) and sameFloat(unit, on) and ignoreCheck(on, unit, "delet") then
            if timecheck(unit,"be","delet") and (timecheckUs(on)) then
              doXWX()
            else
              addUndo({"timeless_crash_add"})
              timeless_crash = true
              addParticles("bonus", unit.x, unit.y, getUnitColor(unit))
            end
          end
        end
      end
    end
    
    to_destroy = handleDels(to_destroy)
    
    local isbonus = getUnitsWithEffect(":o")
    for _,unit in ipairs(isbonus) do
      local stuff = getUnitsOnTile(unit.x, unit.y, {not_destroyed = true, checkmous = true, thicc = thicc_units[unit]})
      for _,on in ipairs(stuff) do
        if hasU(on) and sameFloat(unit, on) and ignoreCheck(on, unit, ":o") then
          writeSaveFile(true, {"levels", level_filename, "bonus"})
          if timecheck(unit,"be",":o") and (timecheckUs(on)) then
            table.insert(to_destroy, unit)
            playSound("bonus")
          else
            table.insert(time_destroy,{unit.id,timeless})
						addUndo({"time_destroy",unit.id})
            table.insert(time_sfx,"bonus")
          end
          addParticles("bonus", unit.x, unit.y, getUnitColor(unit))
        end
      end
    end
    
    local isbonus = getUnitsWithEffect("anti :o")
    for _,unit in ipairs(isbonus) do
      local stuff = getUnitsOnTile(unit.x, unit.y, {not_destroyed = true, checkmous = true, thicc = thicc_units[unit]})
      for _,on in ipairs(stuff) do
        if hasU(on) and sameFloat(unit, on) and ignoreCheck(on, unit, ":o") then
          writeSaveFile(true, {"levels", level_filename, "bonus"})
          if timecheck(unit,"be","anti :o") and (timecheckUs(on)) then
            table.insert(to_destroy, on)
            playSound("bonus")
          else
            table.insert(time_destroy,{on.id,timeless})
						addUndo({"time_destroy",on.id})
            table.insert(time_sfx,"bonus")
          end
          addParticles("bonus", on.x, on.y, getUnitColor(on))
        end
      end
    end
    
    to_destroy = handleDels(to_destroy)
    
    local is2edit = getUnitsWithEffect("2edit")
    for _,unit in ipairs(is2edit) do
      local stuff = getUnitsOnTile(unit.x,unit.y, {not_destroyed = true, checkmous = true, thicc = thicc_units[unit]})
      for _,on in ipairs(stuff) do
        if hasU(on) and sameFloat(unit, on) and ignoreCheck(on, unit, "2edit") then
          scene = editor
        end
      end
    end
    
    local isunwin = getUnitsWithEffect("un:)")
    for _,unit in ipairs(isunwin) do
      local stuff = getUnitsOnTile(unit.x,unit.y, {not_destroyed = true, checkmous = true, thicc = thicc_units[unit]})
      for _,on in ipairs(stuff) do
        if hasU(on) and sameFloat(unit, on) and ignoreCheck(on, unit, "un:)") then
          if timecheck(unit,"be","d") and (timecheckUs(on)) then
            unwins = unwins + 1
          else
            addUndo({"timeless_unwin_add", on.id})
            table.insert(timeless_unwin,on.id)
            addParticles("bonus", unit.x, unit.y, getUnitColor(unit))
          end
        end
      end
    end
    
    local iswin = getUnitsWithEffect(":)")
    for _,unit in ipairs(iswin) do
      local stuff = getUnitsOnTile(unit.x, unit.y, {not_destroyed = true, checkmous = true, thicc = thicc_units[unit]})
      for _,on in ipairs(stuff) do
        if hasU(on) and sameFloat(unit, on) and ignoreCheck(on, unit, ":)") then
          if timecheck(unit,"be",":)") and (timecheckUs(on)) then
            wins = wins + 1
          else
            addUndo({"timeless_win_add", on.id})
            table.insert(timeless_win,on.id)
            addParticles("bonus", unit.x, unit.y, getUnitColor(unit))
          end
        end
      end
    end
    
    local issoko = matchesRule(nil,"soko","?")
    for _,ruleparent in ipairs(issoko) do
      local unit = ruleparent[2]
      local others = {}
      if ruleparent[1].rule.object.name == "themself" then
        others = {unit}
      else
        others = findUnitsByName(ruleparent[1].rule.object.name)
      end
      local fail = false
      if #others > 0 then
        for _,other in ipairs(others) do
          if other == outerlvl then
            local success = false
            for _,on in ipairs(units) do
              if sameFloat(on,outerlvl) and inBounds(on.x, on.y) then
                success = true
                break
              end
            end
            if not success then
              fail = true
              break
            end
          else
            local ons = getUnitsOnTile(other.x,other.y,{exclude = other, thicc = hasProperty(other,"thicc")})
            local success = false
            for _,on in ipairs(ons) do
              if sameFloat(other,on) and ignoreCheck(other,on) then
                success = true
                break
              end
            end
            if not success then
              fail = true
              break
            end
          end
        end
      else fail = true end
      if not fail then
        local stuff = getUnitsOnTile(unit.x,unit.y,{thicc = thicc_units[unit]})
        for _,on in ipairs(stuff) do
          if hasU(on) and sameFloat(unit,on) and ignoreCheck(on,unit) then
            wins = wins + 1
          end
        end
      end
    end
    
    local issuper = getUnitsWithEffect("anti delet")
    local lvltransforms = {}
    for _,unit in ipairs(issuper) do
      local stuff = getUnitsOnTile(unit.x, unit.y, {not_destroyed = true, checkmous = true, thicc = thicc_units[unit]})
      for _,on in ipairs(stuff) do
        if hasU(on) and sameFloat(unit, on) and ignoreCheck(on, unit, ":)") then
          if timecheck(unit,"be","anti delet") and (timecheckUs(on)) then
            writeSaveFile(true, {"levels", level_filename, "won"})
            writeSaveFile(true, {"levels", level_filename, "bonus"})
            table.insert(lvltransforms, unit.name)
          else
            addUndo({"timeless_win_add", on.id})
            table.insert(timeless_win,on.id)
            addParticles("bonus", unit.x, unit.y, getUnitColor(unit))
          end
        end
      end
      if #lvltransforms > 0 then
        doWin("transform", lvltransforms)
      end
    end

    local isnxt = getUnitsWithEffect("nxt")
    for _,unit in ipairs(isnxt) do
      local stuff = getUnitsOnTile(unit.x, unit.y, {not_destroyed = true, checkmous = true, thicc = hasProperty(unit,"thicc")})
      for _,on in ipairs(stuff) do
        if hasU(on) and sameFloat(unit, on) and ignoreCheck(on, unit, "nxt") then
          if timecheck(unit,"be","nxt") and (timecheckUs(on)) then
            doWin("nxt")
          else
            --addUndo({"timeless_win_add", on.id})
            --table.insert(timeless_win,on.id)
            --addParticles("bonus", unit.x, unit.y, getUnitColor(unit))
          end
        end
      end
    end


    local function doOneCreate(rule, creator, createe)
      local object = createe
      if (createe == "txt") then
        createe = "txt_"..creator.fullname
      end
      
      local tile = getTile(createe)
      --let x ben't x txt prevent x be txt, and x ben't txt prevent x be y txt
      local overriden = false;
      if object == "txt" then
        overriden = hasRule(creator, "creatn't", "txt_" .. creator.fullname)
      elseif object:starts("txt_") then
        overriden = hasRule(creator, "creatn't", "txt")
      end
      if tile ~= nil and not overriden then
        local others = getUnitsOnTile(creator.x, creator.y, {name = createe, not_destroyed = true, thicc = hasProperty(creator,"thicc")})
        if #others == 0 then
          local color = rule.object.prefix
          if color == "samepaint" then
            color = colour_for_palette[getUnitColor(creator)[1]][getUnitColor(creator)[2]]
          end
          local new_unit = createUnit(tile.name, creator.x, creator.y, creator.dir, nil, nil, nil, color)
          if new_unit ~= nil then
            addUndo({"create", new_unit.id, false})
          end
        end
      elseif createe == "mous" then
        local new_mouse = createMouse(creator.x, creator.y)
        addUndo({"create_cursor", new_mouse.id})
      end
    end
    
    local creators = matchesRule(nil, "creat", "?")
    for _,match in ipairs(creators) do
      local creator = match[2]
      local createe = match[1].rule.object.name
      if timecheck(creator,"creat",createe) then
        if (group_names_set[createe] ~= nil) then
          for _,v in ipairs(namesInGroup(createe)) do
            doOneCreate(match[1].rule, creator, v)
          end
        else
          doOneCreate(match[1].rule, creator, createe)
        end
      end
    end

    local revived_units = {}
    local zombies = matchesRule("?", "be", "zomb")
    for _,match in ipairs(zombies) do
      local name = match.rule.subject.name
      for i,undos in ipairs(undo_buffer) do
        if i > 1 then
          for _,v in ipairs(undos) do
            if v[1] == "remove" and not zomb_undos[v] then
              unit = createUnit(v[2], v[3], v[4], v[5], nil, v[7])
              if unit ~= nil then
                unit.special = v[8]

                if (unit.name == name or unit.fullname == name) and testConds(unit, match.rule.subject.conds) then
                  table.insert(revived_units, {v[2], v[3], v[4], v[5], v[7], v[8], v}) --im sorry
                end

                deleteUnit(unit, false, true)
              end
            end
          end
        end
      end
    end
    for _,v in ipairs(revived_units) do
      -- aaaaaaaaaa
      zomb_undos[v[7]] = true
      unit = createUnit(v[1], v[2], v[3], v[4], true, v[5])
      if unit ~= nil then
        unit.special = v[6]
      end
      addParticles("bonus", unit.x, unit.y, getUnitColor(unit))
      addUndo({"zomb", unit.id, v[7]})
    end
    
    if not timeless then
      wins = wins + #timeless_win
      unwins = unwins + #timeless_unwin
      for i,win in ipairs(timeless_win) do
        addUndo("timeless_win_remove",win)
        table.remove(timeless_win,i)
      end
      for i,unwin in ipairs(timeless_unwin) do
        addUndo("timeless_unwin_remove",unwin)
        table.remove(timeless_unwin,i)
      end
    end
    
    if wins > unwins then
      doWin("won")
    elseif unwins > wins then
      doWin("won", false)
    end
    
    doDirRules()
  end
  
  DoDiscordRichPresence()
  
  for i,unit in ipairs(units) do
    local deleted = false
    for _,del in ipairs(del_units) do
      if del == unit then
        deleted = true
      end
    end
    
    if not deleted and not unit.removed_final then
      if unit.removed then
        table.insert(del_units, unit)
      end
    end
  end

  deleteUnits(del_units,false)
  
  --Fix the 'txt be undo' bug by checking an additional time if we need to unset backer_turn for a unit.
  if (big_update and not undoing) then
    local backed_this_turn = {}
    local not_backed_this_turn = {}
    
    local isback = getUnitsWithEffectAndCount("undo")
    if hasProperty(outerlvl, "undo") then
      for _,unit in ipairs(units) do
        if isback[unit] then
          isback[unit] = isback[unit] + 1
        else
          isback[unit] = 1
        end
      end
    end
    for unit,amt in pairs(isback) do
      unit = units_by_id[unit] or cursors_by_id[unit]
      backed_this_turn[unit] = true
    end
    
    for unit,turn in pairs(backers_cache) do
      if turn ~= nil and not backed_this_turn[unit] then
        not_backed_this_turn[unit] = true
      end
    end
    
    for unit,_ in pairs(not_backed_this_turn) do
      --print("oh no longer a backer huh, neat", unit.fullname)
      addUndo({"backer_turn", unit.id, unit.backer_turn})
      unit.backer_turn = nil
      backers_cache[unit] = nil
    end
  end
  
  if (will_undo) or (timeless_reset and not timeless) then
    addUndo({"timeless_reset_remove"})
    timeless_reset = false
    doTryAgain()
  end
  
  if timeless_replay and not timeless then
    addUndo({"timeless_replay_remove"})
    timeless_replay = false
    tryStartReplay(true)
  end
  
  if timeless_crash and not timeless then
    addUndo({"timeless_crash_remove"})
    doXWX()
  end
end

function miscUpdates(state_change)
  updateGraphicalPropertyCache(state_change)
  
  for i,unit in ipairs(units) do
    if not deleted and not unit.removed_final then
      local tile = getTile(unit.tile)
      unit.layer = unit.layer + (hasProperty(unit,"curse") and 24 or 0) + (hasProperty(unit,"anti stelth") and 130 or 0)
      if (0 < (graphical_property_cache["flye"][unit] or 0)) then
        unit.layer = unit.layer + 15 + 5 * (graphical_property_cache["flye"][unit] or 0)
      end
      unit.sprite = deepCopy(tile.sprite)
      
      if unit.fullname == "boooo" then
        if hasProperty(unit,"shy...") then
          unit.sprite = {"boooo_shy","boooo_mouth_shy","boooo_blush"}
        elseif graphical_property_cache["slep"][unit] ~= nil then
          unit.sprite = {"boooo_slep","boooo_mouth_slep"}
        else
          unit.sprite = {"boooo","boooo_mouth"}
        end
      end
      
      if unit.fullname == "casete" then
        if unit.color_override then
          local color = colour_for_palette[unit.color_override[1]][unit.color_override[2]]
          if color == "bleu" or color == "cyeann" then
            unit.sprite = {"casete_bleu"}
          elseif color == "reed" or color == "pinc" then
            unit.sprite = {"casete_pinc"}
          elseif color == "orang" or color == "yello" then
            unit.sprite = {"casete_yello"}
          elseif color == "grun" then
            unit.sprite = {"casete_grun"}
          else
            unit.sprite = {"casete_wut"}
          end
        else
          unit.sprite = {"casete_wut"}
        end
        if not hasProperty(unit,"nogo") then
          unit.sprite = {unit.sprite[1].."_sunk"}
        end
      end
      
      if unit.fullname == "bolble" then
        if unit.color_override then
          local color = colour_for_palette[unit.color_override[1]][unit.color_override[2]]
          if color == "whit" then
            unit.sprite = {"bolble_snow"}
          elseif color == "bleu" then
            unit.sprite = {"bolble_waves"}
          elseif color == "cyeann" then
            unit.sprite = {"bolble_12"}
          elseif color == "purp" then
            unit.sprite = {"bolble_clock"}
          elseif color == "brwn" then
            unit.sprite = {"bolble_choco"}
          elseif color == "blacc" then
            unit.sprite = {"bolble_twirl"}
          elseif color == "graey" then
            unit.sprite = {"bolble_checker"}
          elseif color == "orang" then
            unit.sprite = {"bolble_dots"}
          elseif color == "pinc" then
            unit.sprite = {"bolble_hearts"}
          elseif color == "yello" then
            unit.sprite = {"bolble_stars"}
          elseif color == "grun" then
            unit.sprite = {"bolble_tree"}
          else
            unit.sprite = {"bolble"}
          end
        end
      end
      
      if unit.fullname == "ches" then
        if hasProperty(unit,"nedkee") then
          unit.sprite = {"chest_close"}
        else
          unit.sprite = {"chest_open"}
        end
      end
      
      if unit.fullname == "mimi" then
        if graphical_property_cache["slep"][unit] ~= nil then
          unit.sprite = {"mimic_sleep"}
        elseif hasProperty(unit,"nedkee") then
          unit.sprite = {"mimic_close"}
        else
          unit.sprite = {"mimic_open"}
        end
      end
      
      if unit.fullname == "pumkin" then
        if hasProperty(unit,"sans") or hasProperty(unit,":(") or hasProperty(unit,"brite") or hasProperty(unit,"torc") or hasRule(unit,"spoop","?") then
          if graphical_property_cache["slep"][unit] ~= nil then
            unit.sprite = {"pumkin_slep"}
          else
            unit.sprite = {"pumkin_jack"}
          end
        else
          unit.sprite = {"pumkin"}
        end
      end
      
      -- here goes the legendary ditto transformations
      if unit.fullname == "ditto" then
        --very low priority, will only trigger if nothing else does
        if hasRule(unit,"spoop","?") then 
          unit.sprite = {"ditto_spoop"}
        elseif hasRule(unit,"sing","?") then
          unit.sprite = {"ditto_sing"}
        elseif hasRule(unit,"paint","?") then
          unit.sprite = {"ditto_paint"}
        elseif hasProperty(unit,"right") or hasProperty(unit,"downright") or hasProperty(unit,"down") or hasProperty(unit,"downleft") or hasProperty(unit,"left") or hasProperty(unit,"upleft") or hasProperty(unit,"up") or hasProperty(unit,"upright") then
          unit.sprite = {"ditto_direction"}
        elseif hasRule(unit,"snacc","?") then
          unit.sprite = {"ditto_snacc"}
        else
          unit.sprite = {"ditto"}
        end

        local props_to_check = {"stelth","sans","delet","dragbl","rong","wurd","nodrag","rithere","thr","ouch","protecc","noundo",
        "poortoll","go","folowal","tall","rave","colrful","torc","split","icyyyy","icy","hopovr","nuek","knightstep","diagstep","sidestep","notranform",
        "munwalk","visitfren","walk","noswim","haetflor","haetskye","glued","flye","enby","tranz","comepls","goawaypls","goooo",
        "moar","nedkee","fordor","hotte","fridgd","nogo","thingify","y'all","utres","utoo","u",
        } --props are checked in order, so less common props should go in front
        for _,prop in ipairs(props_to_check) do
          if hasProperty(unit,prop) then
            unit.sprite = {"ditto_"..prop}
            break
          end
        end
        --very high priority, will trigger over other things
        if hasProperty(unit,"qt") then
          -- Eeveelutions
          if hasProperty(unit,"icy") then
            unit.sprite = {"ditto_qt_icy"}
          elseif hasProperty(unit,"hopovr") then
            unit.sprite = {"ditto_qt_hopovr"}
          else
            unit.sprite = {"ditto_qt"}
          end
        elseif hasRule(unit,"got","which") then
          unit.sprite = {"ditto_which"}
        elseif hasRule(unit,"got","sant") then
          unit.sprite = {"ditto_sant"}
        elseif hasRule(unit,"got","gunne") then
          unit.sprite = {"ditto_gunne"}
        elseif graphical_property_cache["slep"][unit] ~= nil then
          unit.sprite = {"ditto_slep"}
        elseif hasProperty(unit,"un:)") then
          unit.sprite = {"ditto_;d"}
        elseif hasProperty(unit,":)") then
          unit.sprite = {"ditto_yay"}
        elseif hasProperty(unit,":o") then
          unit.sprite = {"ditto_whoa"}
        end
      end
      
      if unit.fullname == "fube" then
        if hasProperty(unit,"haetskye") or hasProperty(unit,"haetflor") or hasRule(unit,"yeet","?") or hasRule(unit,"moov","?") then
          unit.sprite = {"fube_cube","fube_arrow"}
        else
          unit.sprite = {"fube_arrow","fube_cube"}
        end
      end
      
      if unit.fullname == "bup" then
        if hasProperty(unit,"torc") then
          unit.sprite = {"bup","bup_band","bup_capn","bup_light"}
        else
          unit.sprite = {"bup","no1","no1","no1"}
        end
      end
      
      if unit.fullname == "maglit" then
        if hasProperty(unit,"torc") then
          unit.sprite = {"maglit", "maglit_lit"}
        else
          unit.sprite = {"maglit", "no1"}
        end
      end
      
      if unit.fullname == "die" and (first_turn or not (hasProperty(unit,"stukc") or hasProperty(unit,"noturn"))) then
        local roll = math.random(6)
        unit.sprite[2] = "die_"..roll
      end

      if unit.fullname == "txt_katany" then
        unit.sprite = {"txt/katany"}
        if rules_with_unit[unit] then
          for _,rules in ipairs(rules_with_unit[unit]) do
            if rules.rule.object.unit == unit then
              local tile = getTile(rules.rule.subject.name)
              if tile and tile.features.katany and tile.features.katany.nya then
                unit.sprite = {"txt/katanya"}
              end
            end
          end
        end
      end
      
      if unit.name == "byc" and scene ~= editor then -- playing cards
        if not card_for_id[unit.id] then
          card_for_id[unit.id] = {math.random(13), ({"spade","heart","clubs","diamond"})[math.random(4)]}
        end
        local num, suit = unpack(card_for_id[unit.id])
        print("a")
        unit.sprite[2] = "byc_"..num
        unit.sprite[3] = "byc_"..suit
        if suit == "spade" or suit == "clubs" then
          unit.color = {{0, 3}, {0, 0}, {0, 0}}
          unit.painted = {{0, 0}, false, false}
        end
      end

      if unit.fullname == "txt_niko" then
        if hasProperty(unit,"brite") or hasProperty(unit,"torc") then
          unit.sprite = {"txt/niko", "txt/niko_lit"}
        else
          unit.sprite = {"txt/niko", "no1"}
        end
      end

      unit.overlay = {}
      for name,overlay in pairs(overlay_props) do
        if graphical_property_cache[name][unit] ~= nil then
          table.insert(unit.overlay, overlay.sprite)
        end
      end
      
      -- for optimisation in drawing
      local objects_to_check = {
      "stelth", "colrful", "delet", "rave"
      }
      for name,_ in pairs(overlay_props) do
        table.insert(objects_to_check, name)
      end

      for i = 1, #objects_to_check do
        local prop = objects_to_check[i]
        unit[prop] = graphical_property_cache[prop][unit] ~= nil
      end

      if not units_by_layer[unit.layer] then
        units_by_layer[unit.layer] = {}
      end
      table.insert(units_by_layer[unit.layer], unit)
      max_layer = math.max(max_layer, unit.layer)
    end
  end
  
  mergeTable(still_converting, still_gone)

  for _,unit in ipairs(still_converting) do
    if not units_by_layer[unit.layer] then
      units_by_layer[unit.layer] = {}
    end
    if not table.has_value(units_by_layer[unit.layer], unit) then
      table.insert(units_by_layer[unit.layer], unit)
    end
    max_layer = math.max(max_layer, unit.layer)
  end

  if state_change then
    if units_by_name["camra"] and #units_by_name["camra"] > 1 then
      local removed = {}
      local new_special = {}
      for i,camra in ipairs(units_by_name["camra"]) do
        if i ~= #units_by_name["camra"] then
          table.insert(removed, camra)
          new_special = camra.special.camera
        else
          camra.special.camera = new_special
        end
      end
      for _,camra in ipairs(removed) do
        deleteUnit(camra)
      end
    end
  end
end

function updateGraphicalPropertyCache(state_change)
  for prop,tbl in pairs(graphical_property_cache) do
    --only flye has a stacking graphical effect and we want to ignore selector, the rest are boolean
    --local count = false
    new_tbl = {}
    if (prop == "flye") then
      local prop = getUnitsWithEffectAndCount("flye")
      local anti = getUnitsWithEffectAndCount("anti flye")
      --local ccount = 0
      for unit,amt in pairs(prop) do
        unit = units_by_id[unit] or cursors_by_id[unit]
        new_tbl[unit] = amt or nil
      end
      for unit,amt in pairs(anti) do
        unit = units_by_id[unit] or cursors_by_id[unit]
        new_tbl[unit] = (new_tbl[unit] or 0) - (amt or 0)
      end
    --[[else if (count) then
      local isprop = getUnitsWithEffectAndCount(prop)
      for unit,amt in pairs(isprop) do
        unit = units_by_id[unit] or cursors_by_id[unit]
        new_tbl[unit] = unit.fullname ~= "selctr" and amt or nil
      end]]
    else
      local isprop = getUnitsWithEffect(prop)
      for _,unit in pairs(isprop) do
        new_tbl[unit] = true
      end
    end
    graphical_property_cache[prop] = new_tbl
  end
  
  if state_change then
    updateUnitColours()
  end
end

--Colour logic:
--If a unit be colour, it becomes that colour until it ben't that colour or it be a different colour. It persists even after breaking the rule.
function updateUnitColours()
  to_update = {}
  
  for colour,palette in pairs(main_palette_for_colour) do
    local decolour = matchesRule(nil,"ben't",colour)
    for _,match in ipairs(decolour) do
      local unit = match[2]
      if (unit[colour] == true) then
        addUndo({"colour_change", unit.id, colour, true})
        unit[colour] = false
        to_update[unit] = {}
      end
      --If a unit ben't its native colour, make it blacc.
      if palette[1] == getTile(unit.tile).color[1] and palette[2] == getTile(unit.tile).color[2]  and unitNotRecoloured(unit) then
        addUndo({"colour_change", unit.id, "blacc", false})
        unit["blacc"] = true
        to_update[unit] = {}
      end
    end
    
    local newcolour = matchesRule(nil,"be",colour)
    for _,match in ipairs(newcolour) do
      local unit = match[2]
      if (unit[colour] ~= true) then
        if to_update[unit] == nil then
          to_update[unit] = {}
        end
        table.insert(to_update[unit], colour)
      end
    end
  end
  
  local painting = matchesRule(nil, "paint", "?")
  for _,ruleparent in ipairs(painting) do
    local unit = ruleparent[2]
    local stuff = getUnitsOnTile(unit.x, unit.y, {not_destroyed = true, checkmous = true, thicc = thicc_units[unit]})
    for _,on in ipairs(stuff) do
      if (unit ~= on or ruleparent[1].rule.object.name == "themself") and hasRule(unit, "paint", on) and sameFloat(unit, on) and ignoreCheck(on, unit, "paint") then
        if timecheck(unit,"paint",on) and timecheck(on) then
          local old_colour = getUnitColor(unit)
          local colour = colour_for_palette[old_colour[1]][old_colour[2]]
          if (colour ~= nil and on[colour] ~= true) then
            if to_update[on] == nil then
              to_update[on] = {}
            end
            table.insert(to_update[on], colour)
          end
        end
      end
    end
  end
  
  --BEN'T PAINT removes and prevents all other colour shenanigans.
  local depaint = matchesRule(nil,"ben't","paint")
  for _,match in ipairs(depaint) do
    local unit = match[2]
    unitUnsetColours(unit)
    to_update[unit] = {}
  end
  
  for unit,colours in pairs(to_update) do
    unitUnsetColours(unit)
    for _,colour in ipairs(colours) do
      if (unit[colour] ~= true) then
        addUndo({"colour_change", unit.id, colour, false})
        unit[colour] = true
      end
    end
    updateUnitColourOverride(unit)
  end
end

function unitUnsetColours(unit)
  for colour,palette in pairs(main_palette_for_colour) do
    if unit[colour] == true then
      addUndo({"colour_change", unit.id, colour, true})
      unit[colour] = false
    end
  end
end

function unitNotRecoloured(unit)
  for colour,palette in pairs(main_palette_for_colour) do
    if unit[colour] == true then
      return false
    end
  end
  return true
end

function updateUnitColourOverride(unit)
  unit.color_override = nil
  if unit.pinc then
    unit.color_override = {4, 1}
  elseif unit.purp then
    unit.color_override = {3, 1}
  elseif unit.yello then
    unit.color_override = {2, 4}
  elseif unit.orang then
      unit.color_override = {2, 3}
  elseif unit.cyeann then
    unit.color_override = {1, 4}
  elseif unit.brwn then
    unit.color_override = {6, 0}
  elseif unit.reed then
    unit.color_override = {2, 2}
  elseif unit.grun then
    unit.color_override = {5, 2}
  elseif unit.bleu then
    unit.color_override = {1, 3}
  elseif unit.graey then
    unit.color_override = {0, 1}
  elseif unit.whit then
    unit.color_override = {0, 3}
  elseif unit.blacc then
    unit.color_override = {0, 0}
  end
  --mixing colors
  if (unit.reed and unit.whit) then --pinc
    unit.color_override = {4, 1}
  elseif (unit.reed and unit.grun and unit.bleu) or (unit.reed and unit.cyeann) or (unit.bleu and unit.yello) or (unit.grun and unit.purp) then -- whit
    unit.color_override = {0, 3}
  elseif (unit.reed and unit.bleu) then --purp
    unit.color_override = {3, 1}
  elseif (unit.reed and unit.grun) then --yello
    unit.color_override = {2, 4}
  elseif (unit.reed and unit.yello) then --orang
    unit.color_override = {2, 3}
  elseif (unit.bleu and unit.grun) then --cyeann
    unit.color_override = {1, 4}
  elseif (unit.orang and unit.blacc) then --brwn
    unit.color_override = {6, 0}
  elseif (unit.bleu and unit.yello) then --grun
    unit.color_override = {5, 2}
  elseif (unit.blacc and unit.whit) then --graey
    unit.color_override = {0, 1}
  end
end

function updatePortals()
  for i,unit in ipairs(units) do
    if unit.is_portal and hasProperty(unit, "poortoll") then
      local px, py, move_dir, dir = doPortal(unit, unit.x, unit.y, rotate8(unit.dir), rotate8(unit.dir), true)
      unit.portal.x, unit.portal.y = px, py
      local portal_objects = getUnitsOnTile(px, py, {not_destroyed = true, thicc = thicc_units[unit]})
      unit.portal.objects = portal_objects
      unit.portal.dir = rotate8(unit.dir) - dir
      local new_last_objs = copyTable(unit.portal.objects)
      for _,v in ipairs(unit.portal.last) do
        if not table.has_value(unit.portal.objects, v) then
          table.insert(unit.portal.objects, v)
        end
      end
      table.sort(portal_objects, function(a, b) return a.layer < b.layer end)
      unit.portal.last = new_last_objs
    else
      unit.portal.objects = nil
      unit.portal.last = {}
    end
  end
end

function DoDiscordRichPresence()
  if (discordRPC ~= true) then
    local isu = getUnitsWithEffect("u")
    if (#isu > 0) then
      local unit = isu[1]
      if love.filesystem.read("author_name") == "jill" or unit.fullname == "jill" then
        presence["smallImageText"] = "jill"
        presence["smallImageKey"] = "jill"
      elseif love.filesystem.read("author_name") == "fox" or unit.fullname == "o" then
        presence["smallImageText"] = "o"
        presence["smallImageKey"] = "o"
      elseif unit.fullname == "bab" or unit.fullname == "keek" or unit.fullname == "meem" or unit.fullname == "bup" then
        presence["smallImageText"] = unit.fullname
        presence["smallImageKey"] = unit.fullname
      elseif unit.type == "txt" then
        presence["smallImageKey"] = "txt"
        presence["smallImageText"] = unit.name
      elseif unit.fullname == "os" then
        local os = love.system.getOS()

        if os == "Windows" then
          presence["smallImageKey"] = "windous"
        elseif os == "OS X" then
          presence["smallImageKey"] = "maac" -- i know, the mac name is inconsistent but SHUSH you cant change it after you upload the image
        elseif os == "Linux" then
          presence["smallImageKey"] = "linx"
        else
          presence["smallImageKey"] = "other"
        end

        presence["smallImageText"] = "os"
      else
        presence["smallImageText"] = "other"
        presence["smallImageKey"] = "other"
      end
    else
      presence["smallImageText"] = "nothing :("
      presence["smallImageKey"] = "nothing"
    end
  end
end

function handleDels(to_destroy, unstoppable)
  local convert = false
  local del_units = {}
  for _,unit in ipairs(to_destroy) do
    if unstoppable or not hasProperty(unit, "protecc") then
      unit.destroyed = true
      unit.removed = true
      table.insert(del_units, unit)
    end
  end
  deleteUnits(del_units, false)
  return {}
end

function handleTimeDels(time_destroy)
  local convert = false
  local del_units = {}
  local already_added = {}
  for _,data in ipairs(time_destroy) do
    local unitid = data[1]
    if unitid > 0 then
      unit = units_by_id[unitid]
    else
      unit = cursors_by_id[unitid]
    end
    addUndo({"time_destroy_remove", {unitid,timeless}})
    if unit ~= nil and not hasProperty(unit, "protecc") and timeless == not data[2] then
      if not already_added[unitid] then
        addParticles("destroy",unit.x,unit.y,getUnitColor(unit))
      end
      unit.destroyed = true
      unit.removed = true
      table.insert(del_units,unit)
      already_added[unitid] = true
      for i,win in ipairs(timeless_win) do
        if unit.id == win then
          addUndo({"timeless_win_remove", win})
          table.remove(timeless_win,i)
        end
      end
      for i,unwin in ipairs(timeless_unwin) do
        if unit.id == unwin then
          addUndo({"timeless_unwin_remove", unwin})
          table.remove(timeless_unwin,i)
        end
      end
      for split,_ in pairs(timeless_split) do
        if unit.id == split then
          addUndo({"timeless_split_remove", split})
          timeless_split[split] = nil
        end
      end
    end
  end
  for _,sound in ipairs(time_sfx) do
    playSound(sound,1/#time_sfx)
  end
  time_sfx = {}
  deleteUnits(del_units, false)
  return {}
end

function levelBlock()
  local to_destroy = {}
  local lvlsafe = hasRule(outerlvl,"got","lvl") or hasProperty(outerlvl,"protecc")
  
  if hasProperty(outerlvl,"notranform") then
    writeSaveFile(nil, {"levels", level_filename, "transform"})
  end
  
  if hasProperty(outerlvl, "infloop") then
    destroyLevel("infloop")
  end
  
  if hasProperty(outerlvl, "visitfren") then
    for _,unit in ipairs(units) do
      if sameFloat(unit,outerlvl) and inBounds(unit.x,unit.y) and ignoreCheck(unit,outerlvl,"visitfren") then
        addUndo({"update", unit.id, unit.x, unit.y, unit.dir})
        if inBounds(unit.x+1,unit.y) then
          moveUnit(unit,unit.x+1,unit.y)
        else
          if inBounds(0,unit.y+1) then
            moveUnit(unit,0,unit.y+1)
          else
            moveUnit(unit,0,0)
          end
        end
        --random version for fun
        --[[
        local tx,ty = math.random(0,mapwidth-1),math.random(0,mapheight-1)
        moveUnit(unit,tx,ty)
        ]]
      end
    end
  end
  
  if hasProperty(outerlvl, "nuek") then
    for _,unit in ipairs(units) do
      if sameFloat(unit, outerlvl) and inBounds(unit.x,unit.y) and ignoreCheck(unit,outerlvl,"nuek") then
        table.insert(to_destroy, unit)
        addParticles("destroy", unit.x, unit.y, {2,2})
      end
    end
  end
  
  to_destroy = handleDels(to_destroy)
  
  local isvs = matchesRule(nil,"vs",outerlvl)
  mergeTable(isvs,matchesRule(outerlvl,"vs",nil))
  for _,ruleparent in ipairs(isvs) do
    local unit = ruleparent[2]
    if unit ~= outerlvl and sameFloat(outerlvl,unit) and inBounds(unit.x,unit.y) then
      local unitmoved = false
      for _,undo in ipairs(undo_buffer[1]) do
        if undo[1] == "update" and undo[2] == unit.id and ((undo[3] ~= unit.x) or (undo[4] ~= unit.y)) then
          unitmoved = true
        end
      end
      if unitmoved and ignoreCheck(outerlvl, unit) then
        destroyLevel("vs")
        if not lvlsafe then return 0,0 end
      end
    end
  end
  
  if hasProperty(outerlvl, "noswim") then
    for _,unit in ipairs(units) do
      if sameFloat(unit, outerlvl) and inBounds(unit.x,unit.y) then
        if ignoreCheck(outerlvl, unit) then
          destroyLevel("sink")
          if not lvlsafe then return 0,0 end
        elseif ignoreCheck(unit, outerlvl, "noswim") then
          table.insert(to_destroy, unit)
          addParticles("destroy", unit.x, unit.y, getUnitColor(unit))
        end
      end
    end
    if #to_destroy > 0 then
      playSound("sink")
      shakeScreen(0.3, 0.1)
    end
  end

  to_destroy = handleDels(to_destroy)
  
  if hasProperty(outerlvl, "ouch") then
    for _,unit in ipairs(units) do
      if sameFloat(unit, outerlvl) and inBounds(unit.x,unit.y) and ignoreCheck(outerlvl, unit) then
        destroyLevel("snacc")
        if not lvlsafe then return 0,0 end
      end
    end
  end
  
  if hasProperty(outerlvl, "hotte") then
    local melters = getUnitsWithEffect("fridgd")
    for _,unit in ipairs(melters) do
      if sameFloat(unit,outerlvl) and inBounds(unit.x,unit.y) and ignoreCheck(unit,outerlvl,"hotte") then
        table.insert(to_destroy, unit)
        addParticles("destroy", unit.x, unit.y, getUnitColor(unit))
      end
    end
    if #to_destroy > 0 then
      playSound("hotte")
    end
  end
  
  to_destroy = handleDels(to_destroy)
  
  if hasProperty(outerlvl, "fridgd") then
    if hasProperty(outerlvl, "hotte") then
      destroyLevel("hotte")
      if not lvlsafe then return 0,0 end
    end
    local melters = getUnitsWithEffect("hotte")
    for _,unit in ipairs(melters) do
      if sameFloat(unit,outerlvl) and inBounds(unit.x,unit.y) and ignoreCheck(outerlvl,unit,"hotte") then
        destroyLevel("hotte")
        if not lvlsafe then return 0,0 end
      end
    end
  end
  
  if hasProperty(outerlvl, ":(") then
    local yous = getUs()
    for _,unit in ipairs(yous) do
      if sameFloat(unit,outerlvl) and inBounds(unit.x,unit.y) and ignoreCheck(unit,outerlvl,":(") then
        table.insert(to_destroy, unit)
        addParticles("destroy", unit.x, unit.y, getUnitColor(unit))
      end
    end
  end
  
  to_destroy = handleDels(to_destroy)
  
  if hasProperty(outerlvl, "nedkee") then
    if hasProperty(outerlvl, "fordor") then
      destroyLevel("unlock")
      if not lvlsafe then return 0,0 end
    end
    local dors = getUnitsWithEffect("fordor")
    for _,unit in ipairs(dors) do
      if sameFloat(unit,outerlvl) and inBounds(unit.x,unit.y) then
        if ignoreCheck(outerlvl,unit,"fordor") then
          destroyLevel("unlock")
        end
        if lvlsafe then
          if ignoreCheck(unit,outerlvl,"nedkee") then
            table.insert(to_destroy, unit)
            addParticles("destroy", unit.x, unit.y, getUnitColor(unit))
          end
        else return 0,0 end
      end
    end
    if #to_destroy > 0 then
      playSound("unlock",0.5)
      playSound("break",0.5)
    end
  end
  
  to_destroy = handleDels(to_destroy)
  
  if hasProperty(outerlvl, "fordor") then
    local kees = getUnitsWithEffect("nedkee")
    for _,unit in ipairs(kees) do
      if sameFloat(unit,outerlvl) and inBounds(unit.x,unit.y) then
        if ignoreCheck(outerlvl,unit,"nedkee") then
          destroyLevel("unlock")
        end
        if lvlsafe then
          if ignoreCheck(unit,outerlvl,"fordor") then
            table.insert(to_destroy, unit)
            addParticles("destroy", unit.x, unit.y, getUnitColor(unit))
          end
        else return 0,0 end
      end
    end
    if #to_destroy > 0 then
      playSound("unlock",0.5)
      playSound("break",0.5)
    end
  end
  
  to_destroy = handleDels(to_destroy)
  
  local issnacc = matchesRule(outerlvl,"snacc",nil)
  for _,ruleparent in ipairs(issnacc) do
    local unit = ruleparent[2]
    if unit ~= outerlvl and sameFloat(outerlvl,unit) and inBounds(unit.x,unit.y) and ignoreCheck(unit,outerlvl) then
      if not hasProperty(outerlvl, "anti lesbad") and not hasProperty(unit, "anti lesbad") then
        addParticles("destroy", unit.x, unit.y, getUnitColor(unit))
        table.insert(to_destroy, unit)
      end
    end
  end
  
  local issnacc = matchesRule(nil,"snacc",outerlvl)
  for _,ruleparent in ipairs(issnacc) do
    local unit = ruleparent[2]
    if unit ~= outerlvl and sameFloat(outerlvl,unit) and inBounds(unit.x,unit.y) and ignoreCheck(outerlvl,unit) then
      if not hasProperty(outerlvl, "anti lesbad") and not hasProperty(unit, "anti lesbad") then
        destroyLevel("snacc")
        if not lvlsafe then return 0,0 end
      end
    end
  end
  
  if #to_destroy > 0 then
    playSound("snacc")
    shakeScreen(0.3, 0.1)
  end
  
  to_destroy = handleDels(to_destroy)
  
  local will_undo = false
  if hasProperty(outerlvl, "tryagain") then
    local yous = getUs()
    for _,unit in ipairs(yous) do
      if sameFloat(unit,outerlvl) and inBounds(unit.x,unit.y) and ignoreCheck(unit,outerlvl,"tryagain") then
        doTryAgain()
      end
    end
  end
  
  if hasProperty(outerlvl, "delet") then
    local yous = getUs()
    for _,unit in ipairs(yous) do
      if sameFloat(unit,outerlvl) and inBounds(unit.x,unit.y) and ignoreCheck(unit,outerlvl,"delet") then
        doXWX()
      end
    end
  end
  
  if hasProperty(outerlvl, ":o") then
    local yous = getUs()
    for _,unit in ipairs(yous) do
      if sameFloat(unit,outerlvl) and inBounds(unit.x,unit.y) and ignoreCheck(outerlvl,unit) then
        writeSaveFile(true, {"levels", level_filename, "bonus"})
        destroyLevel("bonus")
        if not lvlsafe then return 0,0 end
      end
    end
  end
  
  local unwins = 0
  if hasProperty(outerlvl, "un:)") then
    local yous = getUs()
    for _,unit in ipairs(yous) do
      if sameFloat(unit,outerlvl) and inBounds(unit.x,unit.y) and ignoreCheck(unit,outerlvl,"un:)") then
        unwins = unwins + 1
      end
    end
  end
  
  local wins = 0
  if hasProperty(outerlvl, ":)") then
    local yous = getUs()
    for _,unit in ipairs(yous) do
      if sameFloat(unit,outerlvl) and inBounds(unit.x,unit.y) and ignoreCheck(unit,outerlvl,":)") then
        wins = wins + 1
      end
    end
  end
  
  local soko = matchesRule(outerlvl,"soko","?")
  for _,ruleparent in ipairs(soko) do
    local units = findUnitsByName(ruleparent.rule.object.name)
    local fail = false
    if #units > 0 then
      for _,unit in ipairs(units) do
        local ons = getUnitsOnTile(unit.x,unit.y,{exclude = unit, thicc = thicc_units[unit]})
        local success = false
        for _,on in ipairs(ons) do
          if sameFloat(unit,on) and ignoreCheck(unit,on) then
            success = true
            break
          end
        end
        if not success then
          fail = true
          break
        end
      end
    else fail = true end
    if not fail then
      local yous = getUs()
      for _,unit in ipairs(yous) do
        if sameFloat(unit,outerlvl) and inBounds(unit.x,unit.y) and ignoreCheck(unit,outerlvl) then
          wins = wins + 1
        end
      end
    end
  end
  
  if hasProperty(outerlvl, "nxt") then
		table.insert(win_sprite_override, getTile("txt_nxt"));
    doWin("nxt")
  end
  
  if hasProperty(outerlvl, "B)") then
    local yous = getUs()
    for _,unit in ipairs(yous) do
      if sameFloat(unit,outerlvl) and inBounds(unit.x,unit.y) and ignoreCheck(unit,outerlvl,"B)") then
        unit.cool = true
      end
    end
  end
  
  return wins,unwins
end

function changeDirIfFree(unit, dir)
  if canMove(unit, dirs8[dir][1], dirs8[dir][2], dir, {solid_name = unit.name, reason = "dir check"}) then
    addUndo({"update", unit.id, unit.x, unit.y, unit.dir})
    unit.olddir = unit.dir
    updateDir(unit, dir)
    return true
  end
  return false
end

function taxicabDistance(a, b)
  return math.abs(a.x - b.x) + math.abs(a.y - b.y)
end

function bishopDistance(a, b)
  if ((a.x + a.y) % 2) == ((b.x + b.y) % 2) then
    return kingDistance(a, b)
  else
    return -1
  end
end

function kingDistance(a, b)
  return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

function euclideanDistance(a, b)
  return (a.x-b.x)*(a.x-b.x) + (a.y-b.y)*(a.y-b.y)
end

function readingOrderSort(a, b)
  if a.y ~= b.y then
    return a.y < b.y
  elseif a.x ~= b.x then
    return a.x < b.x
  else
    return a.id < b.id
  end
end

function destroyLevel(reason)
	if reason == "infloop" or (not hasRule(outerlvl,"got","lvl") and not hasProperty(outerlvl,"protecc")) then
    level_destroyed = true
  end
  
  transform_results = {}
  local holds = matchesRule(outerlvl,"got","?")
  for _,match in ipairs(holds) do
    if not nameIs(outerlvl, match.rule.object.name) then
      local obj_name = match.rule.object.name
      if obj_name == "txt" then
        istext = true
        obj_name = "txt_" .. match.rule.subject.name
      end
      local tile = getTile(obj_name)
      --let x ben't x txt prevent x be txt, and x ben't txt prevent x be y txt
      local overriden = false;
      if match.rule.object.name == "txt" then
        overriden = hasRule(outerlvl, "gotn't", "txt_" .. match.rule.subject.name)
      elseif match.rule.object.name:starts("txt_") then
        overriden = hasRule(outerlvl, "gotn't", "txt")
      end
      if tile ~= nil and not overriden then
        table.insert(transform_results, tile.name)
        table.insert(win_sprite_override, tile)
      end
    end
  end
  
  addUndo({"destroy_level", reason})
  playSound(reason)
  if reason == "unlock" or reason == "convert" then
    playSound("break")
  end
  
  if reason == "infloop" then
    if hasProperty("infloop","tryagain") then
      doTryAgain()
      level_destroyed = false
    elseif hasProperty("infloop","delet") then
      doXWX()
    elseif hasProperty("infloop",":)") then
      doWin("won")
      level_destroyed = true
    elseif hasProperty("infloop","un:)") then
      doWin("won", false)
      level_destroyed = true
    end
    local berule = matchesRule("infloop","be","?")
    for _,rule in ipairs(berule) do
      local object = getTile(rule.rule.object.name)
      if object then
        table.insert(transform_results, object.name)
        table.insert(win_sprite_override, object)
      end
    end
  end
  
  if level_destroyed then
    local units_to_destroy = {}
    for _,unit in ipairs(units) do
      if inBounds(unit.x, unit.y) or reason == "infloop" then
        table.insert(units_to_destroy, unit);
      end
    end
    for _,unit in ipairs(units_to_destroy) do
      addParticles("destroy", unit.x, unit.y, getUnitColor(unit))
    end
    handleDels(units_to_destroy,true)
    if reason == "infloop" and #transform_results == 0 then
      local new_unit = createUnit("infloop", math.floor(mapwidth/2), math.floor(mapheight/2), 1)
      addUndo({"create", new_unit.id, false})
    end
  end
  
  if (#transform_results > 0) then
    doWin("transform", transform_results)
  end
end

function dropGotUnit(unit, rule)
  --TODO: CLEANUP: Blatantly copypasta'd from convertUnits.
  if unit == outerlvl then
    return
  end
  
  function dropOneGotUnit(unit, rule, obj_name)
    local object = obj_name
    if rule.object.name == "txt" then
      obj_name = "txt_" .. unit.fullname
    end
    if object:starts("this") then
      obj_name = "this"
    end
    local obj_tile = getTile(obj_name)
    --let x ben't x txt prevent x be txt, and x ben't txt prevent x be y txt
    local overriden = false
    if object == "txt" then
      overriden = hasRule(unit, "gotn't", "txt_" .. unit.fullname)
    elseif object:starts("txt_") or object:starts("letter_") then
      overriden = hasRule(unit, "gotn't", "txt")
    end
    if not overriden and (obj_name == "mous" or obj_name == "themself" or obj_tile ~= nil) then
      if obj_name == "themself" then
        if unit.class == "cursor" then
          local new_mouse = createMouse_direct(unit.screenx, unit.screeny)
          addUndo({"create_cursor", new_mouse.id})
        else
          local color = rule.object.prefix
          if color == "samepaint" or not color then
            color = colour_for_palette[getUnitColor(unit)[1]][getUnitColor(unit)[2]]
          end
          local new_unit = createUnit(unit.tile, unit.x, unit.y, unit.dir, false, nil, nil, color)
          addUndo({"create", new_unit.id, false})
          return new_unit
        end
      else
        if obj_name == "mous" then
          local new_mouse = createMouse(unit.x, unit.y)
          addUndo({"create_cursor", new_mouse.id})
        else
          local color = rule.object.prefix
          if color == "samepaint" then
            color = colour_for_palette[getUnitColor(unit)[1]][getUnitColor(unit)[2]]
          end
          local new_unit = createUnit(obj_name, unit.x, unit.y, unit.dir, false, nil, nil, color)
          addUndo({"create", new_unit.id, false})
          return new_unit
        end
      end
    end
  end
  
  local result = nil
  local obj_name = rule.object.name
  if (group_names_set[obj_name] ~= nil) then
    for _,v in ipairs(namesInGroup(obj_name)) do
      result = dropOneGotUnit(unit, rule, v)
    end
  else
    result = dropOneGotUnit(unit, rule, obj_name)
  end
  return result
end

function convertLevel()
  local deconverts = matchesRule(outerlvl,"ben't","lvl")
  if #deconverts > 0 then
    destroyLevel("convert")
    return true
  end
  
  transform_results = {}
  
  local meta = matchesRule(outerlvl,"be","txtify")
  if (#meta > 0) then
   local tile = nil
    local nametocreate = outerlvl.fullname
    for i = 1,#meta do
      nametocreate = "txt_"..nametocreate
    end
    tile = getTile(nametocreate)
    if tile ~= nil then
      table.insert(transform_results, tile.name)
      table.insert(win_sprite_override, tile)
    end
  end

  local converts = matchesRule(outerlvl,"be","?")
  for _,match in ipairs(converts) do
    local object = match.rule.object
    if not (hasProperty(outerlvl, "lvl") or hasProperty(outerlvl, "notranform")) and object.type and (object.type.object or object.name:starts("txt_")) and object.name ~= "no1" then
      if match.rule.object.name == "txt" then
        tile = getTile("txt_lvl")
      elseif match.rule.object.name:starts("this") then
        tile = getTile("this")
      else
        tile = getTile(match.rule.object.name)
      end
      if tile == nil and match.rule.object.name == "every1" then
        for _,v in ipairs(referenced_objects) do
          if not hasRule(outerlvl, "ben't", v) then
            table.insert(transform_results, v)
            table.insert(win_sprite_override, getTile(v))
          end
        end
      end
      --let x ben't x txt prevent x be txt, and x ben't txt prevent x be y txt
      local overriden = false;
      if match.rule.object.name == "txt" then
        overriden = hasRule(outerlvl, "ben't", "txt_" .. match.rule.subject.name)
      elseif match.rule.object.name:starts("txt_") then
        overriden = hasRule(outerlvl, "ben't", "txt")
      end
      if tile ~= nil and not overriden then
        table.insert(transform_results, tile.name)
        table.insert(win_sprite_override, tile)
      end
    end
  end
  
  if (#transform_results > 0) then
    doWin("transform", transform_results)
  end
end

function convertUnits(pass)
  
  if level_destroyed then return end
  if convertLevel() then return end

  local converted_units = {}
  local del_cursors = {}


  local removed_rule = {}
  local removed_rule_unit = {}
  local function removeRuleChain(rule, pride)
    if removed_rule[rule] then return end
    removed_rule[rule] = true
    for _,unit in ipairs(rule.units) do
      if not removed_rule_unit[unit] then
        removed_rule_unit[unit] = true
        table.insert(converted_units, unit)
        local particle_colors = {}
        for _,color in ipairs(overlay_props[pride].colors) do
          table.insert(particle_colors, main_palette_for_colour[color])
        end
        addParticles("bonus", unit.x, unit.y, particle_colors)
        for _,other_rule in ipairs(rules_with_unit[unit]) do
          removeRuleChain(other_rule, pride)
        end
      end
    end
  end

  local pride_flags = {"gay", "tranz", "bi", "pan", "lesbab", "ace", "aro", "enby", "fluid", "πoly"}
  for _,pride in ipairs(pride_flags) do
    if rules_with["anti "..pride] then
      for _,bad in ipairs(rules_with["anti "..pride]) do
        removed_rule = {}
        removed_rule_unit = {}
        removeRuleChain(bad, pride)
      end
    end
  end
  
  local meta = getUnitsWithEffectAndCount("txtify")
  for unit,amt in pairs(meta) do
    unit = units_by_id[unit] or cursors_by_id[unit]
    if (unit.fullname == "mous") then
      local cursor = unit
      local tile = getTile("txt_mous")
      if tile ~= nil then
        table.insert(del_cursors, cursor)
      end
      local new_unit = createUnit(tile.name, unit.x, unit.y, unit.dir, true)
      if (new_unit ~= nil) then
        addUndo({"create", new_unit.id, true, created_from_id = unit.id})
      end
    elseif not unit.new and unit.type ~= "outerlvl" and timecheck(unit,"be","txtify") then
      table.insert(converted_units, unit)
      addParticles("bonus", unit.x, unit.y, getUnitColor(unit))
      local tile = nil
      local nametocreate = unit.fullname
      for i = 1,amt do
        local tile = getTile(nametocreate)
        if tile ~= nil and tile.txtify then
          nametocreate = tile.txtify
        else
          nametocreate = "txt_"..nametocreate
        end
      end
      tile = getTile(nametocreate)
      if tile ~= nil then
        local new_unit = createUnit(tile.name, unit.x, unit.y, unit.dir, true)
        if (new_unit ~= nil) then
          new_unit.special.customletter = unit.special.customletter
          addUndo({"create", new_unit.id, true, created_from_id = unit.id})
        end
      end
    end
  end
  
  local demeta = getUnitsWithEffectAndCount("thingify")
  for unit,amt in pairs(demeta) do
    unit = units_by_id[unit] or cursors_by_id[unit]
    if not unit.new and unit.type ~= "outerlvl" and timecheck(unit,"be","thingify") then
      --remove "txt_" as many times as we're de-metaing
      local nametocreate = unit.fullname
      for i = 1,amt do
        local newname = nametocreate
        local tile = getTile(nametocreate)
        if tile.thingify then
          newname = tile.thingify
        else
          if nametocreate:starts("txt_") then
            newname = nametocreate:sub(5, -1)
          elseif nametocreate:starts("letter_") then
            newname = nametocreate:sub(8, -1)
            if newname == "custom" then
              local letter = unit.special.customletter
              if letter == "aa" or letter == "aaa" or letter == "aaaa" then
                newname = "battry"
              elseif letter == "aaaaa" or letter == "aaaaaa" then
                newname = "aaaaaa"
              end
            end
          end
        end
        if not getTile(newname) then
          break
        end
        nametocreate = newname
      end
      if nametocreate ~= unit.fullname then
        table.insert(converted_units, unit)
        addParticles("bonus", unit.x, unit.y, getUnitColor(unit))
        if (nametocreate == "mous") then
          local new_mouse = createMouse(unit.x, unit.y)
          addUndo({"create_cursor", new_mouse.id, created_from_id = unit.id})
        else
          local tile = getTile(nametocreate)
          if tile ~= nil then
            local new_unit = createUnit(tile.name, unit.x, unit.y, unit.dir, true)
           if (new_unit ~= nil) then
              new_unit.special.customletter = unit.special.customletter
              addUndo({"create", new_unit.id, true, created_from_id = unit.id})
            end
          end
        end
      end
    end
  end

  local ntify = getUnitsWithEffectAndCount("n'tify")
  for unit,amt in pairs(ntify) do
    unit = units_by_id[unit] or cursors_by_id[unit]
    if not unit.new and unit.type ~= "outerlvl" and timecheck(unit,"be","n'tify") then
      local nametocreate = unit.fullname
      for i = 1,amt do
        local newname = nametocreate
        local tile = getTile(nametocreate)
        if nametocreate:ends("n't") then
          newname = nametocreate:sub(1, string.len(nametocreate)-3)
        else
          newname = nametocreate .. "n't"
        end
        if not getTile(newname) then
          break
        end
        nametocreate = newname
      end
      if nametocreate ~= unit.fullname then
        table.insert(converted_units, unit)
        addParticles("bonus", unit.x, unit.y, getUnitColor(unit))
        if (nametocreate == "mous" or nametocreate == "mousn't") then
          local new_mouse = createMouse(unit.x, unit.y)
          addUndo({"create_cursor", new_mouse.id, created_from_id = unit.id})
        else
          local tile = getTile(nametocreate)
          if tile ~= nil then
            local new_unit = createUnit(tile.name, unit.x, unit.y, unit.dir, true)
           if (new_unit ~= nil) then
              new_unit.special.customletter = unit.special.customletter
              addUndo({"create", new_unit.id, true, created_from_id = unit.id})
            end
          end
        end
      end
    end
  end

  local ntifynt = getUnitsWithEffectAndCount("ify")
  for unit,amt in pairs(ntifynt) do
    unit = units_by_id[unit] or cursors_by_id[unit]
    if not unit.new and unit.type ~= "outerlvl" and timecheck(unit,"be","ify") then
      local nametocreate = unit.fullname
      if not getTile(nametocreate) then
        break
      end
      addParticles("bonus", unit.x, unit.y, getUnitColor(unit))
      if (nametocreate == "mous" or nametocreate == "mousn't") then
        break
      end
      table.insert(converted_units, unit)
      local tile = getTile(nametocreate)
      if tile ~= nil then
        local new_unit = createUnit(tile.name, unit.x, unit.y, unit.dir, true)
        if (new_unit ~= nil) then
          new_unit.special.customletter = unit.special.customletter
          addUndo({"create", new_unit.id, true, created_from_id = unit.id})
        end
      end
    end
  end

  local ntifyyy = getUnitsWithEffectAndCount("n'tifyyy")
  for unit,amt in pairs(ntifyyy) do
    unit = units_by_id[unit] or cursors_by_id[unit]
    if not unit.new and unit.type ~= "outerlvl" and timecheck(unit,"be","n'tifyyy") then
      local nametocreate = unit.fullname
      for i = 1,amt do
        local newname = nametocreate
        local tile = getTile(nametocreate)
        newname = nametocreate .. "n't"
        if not getTile(newname) then
          break
        end
        nametocreate = newname
      end
      if nametocreate ~= unit.fullname then
        table.insert(converted_units, unit)
        addParticles("bonus", unit.x, unit.y, getUnitColor(unit))
        if (nametocreate:starts("mous")) then
          local new_mouse = createMouse(unit.x, unit.y)
          addUndo({"create_cursor", new_mouse.id, created_from_id = unit.id})
        else
          local tile = getTile(nametocreate)
          if tile ~= nil then
            local new_unit = createUnit(tile.name, unit.x, unit.y, unit.dir, true)
           if (new_unit ~= nil) then
              new_unit.special.customletter = unit.special.customletter
              addUndo({"create", new_unit.id, true, created_from_id = unit.id})
            end
          end
        end
      end
    end
  end

  local deconverts = matchesRule(nil,"ben't","?")
  for _,match in ipairs(deconverts) do
    local rules = match[1]
    local unit = match[2]

    local rule = rules.rule
    
    if (rule.subject.name == "mous" and rule.object.name == "mous") then
      for _,cursor in ipairs(cursors) do
        if testConds(cursor, rule.subject.conds) then
          addParticles("bonus", unit.x, unit.y, getUnitColor(unit))
          table.insert(del_cursors, cursor)
        end
      end
    elseif not unit.new and nameIs(unit, rule.object.name) and timecheck(unit) then
      if not unit.removed and unit.type ~= "outerlvl" then
        addParticles("bonus", unit.x, unit.y, getUnitColor(unit))
        table.insert(converted_units, unit)
      end
    end
  end

  local haetself = matchesRule(nil,"haet","themself")
  for _,match in ipairs(haetself) do
    local rules = match[1]
    local unit = match[2]

    local rule = rules.rule

    if not unit.new and timecheck(unit) and not unit.removed and unit.type ~= "outerlvl" then
      unit.removed = true
      if unit.class == "cursor" then
        table.insert(del_cursors, cursor)
      else
        table.insert(converted_units, unit)
      end
    end
  end

  local all = matchesRule(nil,"be","every1")
  for _,match in ipairs(all) do
    local rules = match[1]
    local unit = match[2]
    local rule = rules.rule
    if not hasProperty(unit, "notranform") then
      if (rule.subject.name == "mous" and rule.object.name ~= "mous") then
        for _,cursor in ipairs(cursors) do
          if testConds(cursor, rule.subject.conds) then
            for _,v in ipairs(referenced_objects) do
              local tile
              if v == "txt" then
                tile = getTile("txt_" .. rule.subject.name)
              else
                tile = getTile(v)
              end
              if tile ~= nil then
                table.insert(del_cursors, cursor)
              end
              local new_unit = createUnit(tile.name, unit.x, unit.y, unit.dir, true)
              if (new_unit ~= nil) then
                addUndo({"create", new_unit.id, true, created_from_id = unit.id})
              end
            end
          end
        end
      elseif not unit.new and unit.class == "unit" and unit.type ~= "outerlvl" and not hasRule(unit, "be", unit.name) and timecheck(unit) then
        for _,v in ipairs(referenced_objects) do
          local tile
          if v == "txt" then
            tile = getTile("txt_" .. rule.subject.name)
          else
            tile = getTile(v)
          end
          if tile ~= nil then
            if not unit.removed then
              table.insert(converted_units, unit)
            end
            local new_unit = createUnit(tile.name, unit.x, unit.y, unit.dir, true)
            if (new_unit ~= nil) then
              addUndo({"create", new_unit.id, true, created_from_id = unit.id})
            end
          elseif v == "mous" then
            if not unit.removed then
              table.insert(converted_units, unit)
            end
            unit.removed = true
            local new_mouse = createMouse(unit.x, unit.y)
            addUndo({"create_cursor", new_mouse.id, created_from_id = unit.id})
          end
        end
      end
    end
  end
  
  local all2 = matchesRule(nil,"be","every2")
  for _,match in ipairs(all2) do
    local rules = match[1]
    local unit = match[2]
    local rule = rules.rule
    if not hasProperty(unit, "notranform") then
      if (rule.subject.name == "mous" and rule.object.name ~= "mous") then
        for _,cursor in ipairs(cursors) do
          if testConds(cursor, rule.subject.conds) then
            local tbl = copyTable(referenced_objects)
            mergeTable(tbl, referenced_text)
            for _,v in ipairs(tbl) do
              local tile
              if v == "txt" then
                tile = getTile("txt_" .. rule.subject.name)
              else
                tile = getTile(v)
              end
              if tile ~= nil then
                table.insert(del_cursors, cursor)
              end
              local new_unit = createUnit(tile.name, unit.x, unit.y, unit.dir, true)
              if (new_unit ~= nil) then
                addUndo({"create", new_unit.id, true, created_from_id = unit.id})
              end
            end
          end
        end
      elseif not unit.new and unit.class == "unit" and unit.type ~= "outerlvl" and not hasRule(unit, "be", unit.name) and timecheck(unit) then
        local tbl = copyTable(referenced_objects)
        mergeTable(tbl, referenced_text)
        for _,v in ipairs(tbl) do
          local tile
          if v == "txt" then
            tile = getTile("txt_" .. rule.subject.name)
          else
            tile = getTile(v)
          end
          if tile ~= nil then
            if not unit.removed then
              table.insert(converted_units, unit)
            end
            local new_unit = createUnit(tile.name, unit.x, unit.y, unit.dir, true)
            if (new_unit ~= nil) then
              addUndo({"create", new_unit.id, true, created_from_id = unit.id})
            end
          elseif v == "mous" then
            if not unit.removed then
              table.insert(converted_units, unit)
            end
            unit.removed = true
            local new_mouse = createMouse(unit.x, unit.y)
            addUndo({"create_cursor", new_mouse.id, created_from_id = unit.id})
          end
        end
      end
    end
  end
  
  local all3 = matchesRule(nil,"be","every3")
  for _,match in ipairs(all3) do
    local rules = match[1]
    local unit = match[2]
    local rule = rules.rule
    if not hasProperty(unit, "notranform") then
      if (rule.subject.name == "mous" and rule.object.name ~= "mous") then
        for _,cursor in ipairs(cursors) do
          if testConds(cursor, rule.subject.conds) then
            local tbl = copyTable(referenced_objects)
            mergeTable(tbl, referenced_text)
            mergeTable(tbl, special_objects)
            for _,v in ipairs(tbl) do
              local tile
              if v == "txt" then
                tile = getTile("txt_" .. rule.subject.name)
              else
                tile = getTile(v)
              end
              if tile ~= nil then
                table.insert(del_cursors, cursor)
              end
              local new_unit = createUnit(tile.name, unit.x, unit.y, unit.dir, true)
              if (new_unit ~= nil) then
                addUndo({"create", new_unit.id, true, created_from_id = unit.id})
              end
            end
          end
        end
      elseif not unit.new and unit.class == "unit" and unit.type ~= "outerlvl" and not hasRule(unit, "be", unit.name) and timecheck(unit) then
        local tbl = copyTable(referenced_objects)
        mergeTable(tbl, referenced_text)
        mergeTable(tbl, special_objects)
        for _,v in ipairs(tbl) do
          local tile
          if v == "txt" then
            tile = getTile("txt_" .. rule.subject.name)
          else
            tile = getTile(v)
          end
          if tile ~= nil then
            if not unit.removed then
              table.insert(converted_units, unit)
            end
            local new_unit = createUnit(tile.name, unit.x, unit.y, unit.dir, true)
            if (new_unit ~= nil) then
              addUndo({"create", new_unit.id, true, created_from_id = unit.id})
            end
          elseif v == "mous" then
            if not unit.removed then
              table.insert(converted_units, unit)
            end
            unit.removed = true
            local new_mouse = createMouse(unit.x, unit.y)
            addUndo({"create_cursor", new_mouse.id, created_from_id = unit.id})
          end
        end
      end
    end
  end
  
  local converts = matchesRule(nil,"be","?")
  for _,match in ipairs(converts) do
    local rules = match[1]
    local unit = match[2]
    local rule = rules.rule
    
    if not hasProperty(unit, "notranform") then
      if (rule.subject.name == "mous" and rule.object.name ~= "mous") then
        for _,cursor in ipairs(cursors) do
          if testConds(cursor, rule.subject.conds) then
            local tile
            if rule.object.name == "txt" then
              tile = getTile("txt_" .. rule.subject.name)
            elseif rule.object.name:starts("this") and not rule.object.name:ends("n't") then
              tile = getTile("this")
            else
              tile = getTile(rule.object.name)
            end
            local new_special = {}
            if rule.object.name:find("letter_custom") then
              new_special.customletter = rule.object.unit.special.customletter
            end
            if tile ~= nil then
              table.insert(del_cursors, cursor)
              local color = rule.object.prefix
              if color == "samepaint" then
                color = colour_for_palette[getUnitColor(unit)[1]][getUnitColor(unit)[2]]
              end
              local new_unit = createUnit(tile.name, unit.x, unit.y, unit.dir, true, nil, nil, color)
              for k,v in pairs(new_special) do
                new_unit.special[k] = v
              end
              if (new_unit ~= nil) then
                addUndo({"create", new_unit.id, true, created_from_id = unit.id})
              end
            end
          end
        end
      elseif not unit.new and unit.class == "unit" and not nameIs(unit, rule.object.name) and unit.type ~= "outerlvl" and timecheck(unit) then
        local tile
        if rule.object.name == "txt" then
          tile = getTile("txt_" .. rule.subject.name)
        elseif rule.object.name:starts("this") and not rule.object.name:ends("n't") then
          tile = getTile("this")
        else
          tile = getTile(rule.object.name)
        end
        --prevent transformation into certain objects
        if tile ~= nil and not tile.convertible then
          tile = nil
        end
        --let x ben't x txt prevent x be txt, and x ben't txt prevent x be y txt
        local overriden = false;
        if rule.object.name == "txt" then
          overriden = hasRule(unit, "ben't", "txt_" .. rule.subject.name)
        elseif rule.object.name:starts("txt_") then
          overriden = hasRule(unit, "ben't", "txt")
        end
        --transform into custom letter
        local new_special = {}
        if rule.object.name:find("letter_custom") then
          new_special.customletter = rule.object.unit.special.customletter
        end
        if tile ~= nil and not overriden then
          if not unit.removed then
            table.insert(converted_units, unit)
          end
          local color = rule.object.prefix
          if color == "samepaint" then
            color = colour_for_palette[getUnitColor(unit)[1]][getUnitColor(unit)[2]]
          end
          local new_unit = createUnit(tile.name, unit.x, unit.y, unit.dir, true, nil, nil, color)
          if (new_unit ~= nil) then
            if rule.object.name == "lvl" then
              if unit.special.level then
                writeSaveFile(true, {"levels", unit.special.level, "seen"})
                unit.special.visibility = "open"
              end
              if not new_unit.color_override then
                new_unit.color_override = getUnitColor(unit)
              end
            end
            mergeTable(new_unit.special, copyTable(unit.special))
            for k,v in pairs(new_special) do
              new_unit.special[k] = v
            end
            addUndo({"create", new_unit.id, true, created_from_id = unit.id})
          end
        elseif rule.object.name == "mous" then
          if not unit.removed then
            table.insert(converted_units, unit)
          end
          unit.removed = true
          local new_mouse = createMouse(unit.x, unit.y)
          addUndo({"create_cursor", new_mouse.id, created_from_id = unit.id})
        end
      end
    end
  end
  
  if hasProperty(outerlvl, "qt") then
    for x=0,mapwidth-1 do
      for y=0,mapheight-1 do
        if #unitsByTile(x,y) == 0 then
          local new_unit = createUnit("l..uv", x, y, 1, true)
          addUndo{"create", new_unit.id, true}
        end
      end
    end
  end
  
  local moars = getUnitsWithEffect("moar")
  for _,slice in  ipairs(moars) do
    if slice.name == "lie/8" and not hasProperty(unit, "notranform") then
      if not slice.removed then
        table.insert(converted_units, slice)
      end
      local new_unit = createUnit("lie", slice.x, slice.y, slice.dir, true)
      addUndo({"create", new_unit.id, true, created_from_id = slice.id})
    end
  end

  local pans = getUnitsWithEffect("pan")
  for _,cake in  ipairs(pans) do
    if cake.name == "lie" and not hasProperty(unit, "notranform") then
      if not cake.removed then
        table.insert(converted_units, cake)
      end
      local new_unit = createUnit("panlie", cake.x, cake.y, cake.dir, true)
      addUndo({"create", new_unit.id, true, created_from_id = cake.id})
    end
  end
  
  local thes = matchesRule(nil,"be","the")
  for _,ruleparent in ipairs(thes) do
    local unit = ruleparent[2]
    if not hasProperty(unit, "notranform") then
      local the = ruleparent[1].rule.object.unit
      
      local tx = the.x
      local ty = the.y
      local dir = the.dir
      local dx = dirs8[dir][1]
      local dy = dirs8[dir][2]
      dx,dy,dir,tx,ty = getNextTile(the,dx,dy,dir)
      
      local tfd = false
      local tfs = getUnitsOnTile(tx,ty)
      for _,other in ipairs(tfs) do
        if not hasRule(unit,"be",unit.name) and not hasRule(unit,"ben't",other.fullname) then
          local new_unit = createUnit(other.tile, unit.x, unit.y, unit.dir, true)
          if new_unit ~= nil then
            new_unit.special.customletter = other.special.customletter
            tfd = true
            addUndo({"create", new_unit.id, true, created_from_id = unit.id})
          end
        end
      end
      
      if tfd and not unit.removed then
        table.insert(converted_units, unit)
      end
    end
  end

  local deez = matchesRule(nil,"be","deez")
  for _,ruleparent in ipairs(deez) do
    local unit = ruleparent[2]
    if not hasProperty(unit, "notranform") then
      local deez_unit = ruleparent[1].rule.object.unit
      
      local tx = deez_unit.x
      local ty = deez_unit.y
      local dir = deez_unit.dir
      local dx = dirs8[dir][1]
      local dy = dirs8[dir][2]

      local already_checked = {}
      local transform_deez = {}

      while not already_checked[tx..","..ty..":"..dir] do
        already_checked[tx..","..ty..":"..dir] = true

        dx,dy,dir,tx,ty = getNextTile(the,dx,dy,dir,nil,tx,ty)
        
        if not inBounds(tx, ty) then
          break
        else
          local tfs = getUnitsOnTile(tx,ty)
          for _,other in ipairs(tfs) do
            if not transform_deez[other] and not hasRule(unit,"be",unit.name) and not hasRule(unit,"ben't",other.fullname) then
              transform_deez[other] = true
            end
          end
        end
      end

      local tfd = false
      for tf,_ in pairs(transform_deez) do
        local new_unit = createUnit(tf.tile, unit.x, unit.y, unit.dir, true)
        if new_unit ~= nil then
          new_unit.special.customletter = tf.special.customletter
          tfd = true
          addUndo({"create", new_unit.id, true, created_from_id = unit.id})
        end
      end

      if tfd and not unit.removed then
        table.insert(converted_units, unit)
      end
    end
  end

  local babbys = getUnitsWithEffect("thicc")
  for _,babby in ipairs(babbys) do
    if babby.fullname == "babby" and not hasProperty(unit, "notranform") then
      if not babby.removed then
        table.insert(converted_units, babby)
      end
      local new_unit = createUnit("bab", babby.x, babby.y, babby.dir, true)
      addUndo({"create", new_unit.id, true, created_from_id = babby.id})
    end
  end
  
  for i,cursor in ipairs(del_cursors) do
    if (not cursor.removed) then  
      addUndo({"remove_cursor", cursor.screenx, cursor.screeny, cursor.id})
      deleteMouse(cursor.id)
    end
  end

  deleteUnits(converted_units,true)
end

function deleteUnits(del_units,convert,gone)
  for _,unit in ipairs(del_units) do
    if (not unit.removed_final) then
      if (unit.color_override ~= nil) then
        addUndo({"color_override_change", unit.id, unit.color_override})
      end
      for colour,_ in pairs(main_palette_for_colour) do
        if unit[colour] == true then
          addUndo({"colour_change", unit.id, colour, true})
        end
      end
      if (unit.backer_turn ~= nil) then
        addUndo({"backer_turn", unit.id, unit.backer_turn})
      end
      if unit.class == "cursor" then
        addUndo({"remove_cursor",unit.screenx,unit.screeny,unit.id})
      else
        addUndo({"remove", unit.tile, unit.x, unit.y, unit.dir, convert or false, unit.id, unit.special, gone or false})
      end
    end
    if unit.class ~= "cursor" then
      deleteUnit(unit,convert,false,gone)
    else
      deleteMouse(unit.id)
    end
  end
end

function createUnit(tile,x,y,dir,convert,id_,really_create_empty,prefix,anti_gone) --ugh
  local unit = {}
  unit.class = "unit"

  unit.id = newUnitID(id_)
  unit.tempid = newTempID()
  unit.x = x or 0
  unit.y = y or 0
  unit.dir = dir or 1
  unit.active = (scene == editor)
  unit.blocked = false
  unit.removed = false

  unit.old_active = unit.active
  unit.overlay = {}
  unit.used_as = {} -- list of text types, used for determining sprite transformation
  unit.frame = math.random(1, 3)-1 -- for potential animation
  unit.special = {} -- for lvl objects
  unit.portal = {dir = 1, last = {}, extra = {}} -- for hol objects

  local data = getTile(tile, true)

  if not data then
    print(colr.yellow("Failed to create tile: " .. tile))
    data = getTile("wat")
  end

  unit.tile = data.name
  unit.display = data.display
  unit.sprite = deepCopy(data.sprite)
  unit.type = data.is_text and "txt" or "object"
  unit.typeset = data.typeset
	unit.meta = data.meta
  unit.nt = data.nt
  unit.color = deepCopy(data.color)
  unit.painted = deepCopy(data.painted)
  unit.layer = data.layer
  unit.rotate = data.rotate
  unit.wobble = data.wobble
  unit.got_objects = {}
  unit.sprite_transforms = data.sprite_transforms
  unit.features = data.features
  unit.is_portal = data.portal
  if (unit.rotate or (rules_with ~= nil and rules_with["rotatbl"] and hasProperty(unit,"rotatbl"))) then
    unit.rotatdir = dir
  else
    unit.rotatdir = 1
  end
  
  if (not unit_tests) then
    unit.draw = {x = unit.x, y = unit.y, scalex = 1, scaley = 1, rotation = (unit.rotatdir - 1) * 45, opacity = 1}
    if convert then
      unit.draw.scaley = 0
      addTween(tween.new(0.1, unit.draw, {scaley = 1}), "unit:scaley:" .. unit.tempid)
    elseif anti_gone then
      unit.draw.y = unit.y - love.math.random(5,9)
      unit.draw.rotation = (90 + love.math.random(0,180)) * (love.math.random() > .5 and 1 or -1)
      unit.draw.opacity = 0
      local method = love.math.random() > .01 and "outSine" or "outElastic"
      addTween(tween.new(1.5, unit.draw, {opacity = 1}, method), "unit:opacity:" .. unit.tempid)
      addTween(tween.new(1.5, unit.draw, {rotation = 0}, method), "unit:rotation:" .. unit.tempid)
      addTween(tween.new(1.5, unit.draw, {y = unit.y}, method), "unit:pos:" .. unit.tempid)
    end
  end

  unit.fullname = data.name

  if unit.type == "txt" then
    should_parse_rules = true
    unit.name = "txt"
    if unit.typeset.letter then
      letters_exist = true
      unit.textname = string.sub(unit.fullname, 8)
    else
      unit.textname = string.sub(unit.fullname, 5)
    end
  else
    unit.name = unit.fullname
    unit.textname = unit.fullname
  end

  if unit.name == "camra" then
    unit.special.camera = {x = 0, y = 0, w = 11, h = 7, fixed_w = false, fixed_h = false}
  end
  
  if rules_effecting_names[unit.name] then
    should_parse_rules = true
  end
  
  if prefix then
    if type(prefix) == "table" then
      unit.color_override = prefix
      --also set the appropriate initial colour flag
      local color = colour_for_palette[unit.color_override[1]][unit.color_override[2]];
      if color ~= nil then
        unit[color] = true
      end
    else
      unit[prefix] = true
      updateUnitColourOverride(unit)
    end
  end
  
  --abort if we're trying to create outerlvl outside of the start
  if (x < -10 or y < -10) and unit.name == "lvl" and not really_create_empty then
    return
  end
  
  --make outerlvl here
  if ((unit.name == "lvl" or unit.fullname == "lvl") and really_create_empty) then
    unit.type = "outerlvl"
  end
  
  --abort if we're trying to create empty outside of initialization, to preserve the invariant 'there is exactly empty per tile'
  if ((unit.fullname == "no1") and not really_create_empty) then
    --print("not placing an empty:"..unit.name..","..unit.fullname..","..unit.textname)
    return nil
  end
  
  --do this before the 'this' change to textname so that we only get 'this' in referenced_objects
  if unit.typeset.object and unit.textname ~= "every1" and unit.textname ~= "every2" and unit.textname ~= "every3" and unit.textname ~= "mous" and unit.textname ~= "bordr" and unit.textname ~= "no1" and unit.textname ~= "lvl" and unit.textname ~= "the" and unit.textname ~= "deez" and unit.textname ~= "txt" and unit.textname ~= "this" and group_names_set[unit.textname] ~= true then
    if not unit.textname:ends("n't") and not unit.textname:starts("txt_") and not unit.textname:starts("letter_") and not table.has_value(referenced_objects, unit.textname) then
      table.insert(referenced_objects, unit.textname)
    end
  end
  
  if unit.fullname == "this" then
    unit.name = unit.name .. unit.id
    unit.textname = unit.textname .. unit.id
  end
  
  if unit.type == "txt" then
    updateNameBasedOnDir(unit)
    if not table.has_value(referenced_text, unit.fullname) then
      table.insert(referenced_text, unit.fullname)
    end
  end

  units_by_id[unit.id] = unit

  if (not units_by_name[unit.name] and not unit.type ~= "outerlvl") then
    units_by_name[unit.name] = {}
  end
  table.insert(units_by_name[unit.name], unit)

  if unit.fullname ~= unit.name then
    if not units_by_name[unit.fullname] then
      units_by_name[unit.fullname] = {}
    end
    table.insert(units_by_name[unit.fullname], unit)
  end
  
  if unit.name:starts("this") then
    if not units_by_name["txt"] then
      units_by_name["txt"] = {}
    end
    table.insert(units_by_name["txt"], unit)
  end

  if not units_by_layer[unit.layer] then
    units_by_layer[unit.layer] = {}
  end
  table.insert(units_by_layer[unit.layer], unit)
  max_layer = math.max(max_layer, unit.layer)

  table.insert(units, unit)
  
  --keep empty out of units_by_tile - it will be returned in getUnitsOnTile
  if (not (unit.fullname == "no1" or unit.type == "outerlvl")) then
    table.insert(unitsByTile(x, y), unit)
    if rules_with ~= nil and rules_with["thicc"] and hasProperty(unit, "thicc") then
      unit.draw.thicc = 2
      table.insert(unitsByTile(x+1, y), unit)
      table.insert(unitsByTile(x, y+1), unit)
      table.insert(unitsByTile(x+1, y+1), unit)
      thicc_units[unit] = true;
    end
  end

  --updateDir(unit, unit.dir)
  new_units_cache[unit] = true
  unit.new = true
  --print("createUnit:", unit.fullname, unit.id, unit.x, unit.y)
  return unit
end

function deleteUnit(unit,convert,undoing,gone)
  print("aaaa", thicc_units[unit])
  unit.removed = true
  unit.removed_final = true
  if not undoing and not convert and not gone and not level_destroyed and rules_with ~= nil then
    gotters = matchesRule(unit, "got", "?")
    for _,ruleparent in ipairs(gotters) do
      local rule = ruleparent.rule
      local new_unit = dropGotUnit(unit, rule)
      --thicc got law
      if (thicc_units[unit] and new_unit ~= nil and not thicc_units[new_unit]) then
        local old_x, old_y = unit.x, unit.y
        for i=1,3 do
          unit.x = old_x+i%2;
          unit.y = old_y+math.floor(i/2);
          dropGotUnit(unit, rule)
        end
        unit.x = old_x
        unit.y = old_y
      end
    end
  end
  --empty can't really be destroyed, only pretend to be, to preserve the invariant 'there is exactly empty per tile'
  if (unit.fullname == "no1" or unit.type == "outerlvl") then
    unit.destroyed = false
    unit.removed = false
    unit.removed_final = false
    return
  end
  if unit.type == "txt" or rules_effecting_names[unit.name] then
    should_parse_rules = true
  end
  removeFromTable(units, unit)
  units_by_id[unit.id] = nil
  removeFromTable(units_by_name[unit.name], unit)
  if unit.name ~= unit.fullname then
    removeFromTable(units_by_name[unit.fullname], unit)
  end
  removeFromTable(unitsByTile(unit.x, unit.y), unit)
  if thicc_units[unit] then
    removeFromTable(unitsByTile(unit.x+1,unit.y),unit)
    removeFromTable(unitsByTile(unit.x,unit.y+1),unit)
    removeFromTable(unitsByTile(unit.x+1,unit.y+1),unit)
    thicc_units[unit] = nil
  end
  if not convert and not gone then
    removeFromTable(units_by_layer[unit.layer], unit)
  end
  if not unit_tests then
    if convert then
      table.insert(still_converting, unit)
      addUndo{"tween",unit}
      addTween(tween.new(0.1, unit.draw, {scaley = 0}), "unit:scaley:" .. unit.tempid)
      tick.delay(function() removeFromTable(still_converting, unit) end, 0.1)
    elseif gone then
      if unit.fullname == "ditto" then
        if hasProperty(unit,"notranform") then
            unit.sprite = {"ditto_notranform"}
        else
            unit.sprite = {"ditto_gone"}
        end
      end
      table.insert(still_converting, unit)
      addUndo{"tween",unit}
      local rise = love.math.random(5,9)
      local rotate = (90 + love.math.random(0,180)) * (love.math.random() > .5 and 1 or -1)
      local method = love.math.random() > .01 and "inSine" or "inElastic"
      addTween(tween.new(1.5, unit.draw, {y = unit.y-rise, rotation = rotate, opacity = 0}, method), "unit:rotation:" .. unit.tempid)
      tick.delay(function() removeFromTable(still_converting, unit) end, 1.5)
    end
  end
end

function moveUnit(unit,x,y,portal,instant)
  --print("moving:", unit.fullname, unit.x, unit.y, "to:", x, y)
  --when empty moves, swap it with the empty in its destination tile, to preserve the invariant 'there is exactly empty per tile'
  --also, keep empty out of units_by_tile - it will be added in getUnitsOnTile
  if (unit.type == "outerlvl") then
  elseif (unit.name == "mous") then
    --find out how far apart two tiles are in screen co-ordinates
    local x0,y0 = gameTileToScreen(0,0)
    local x1,y1 = gameTileToScreen(1,1)
    local dx = x1-x0
    local dy = y1-y0
    local oldx = unit.x
    local oldy = unit.y
    local mx = dx*(x-oldx)
    local my = dy*(y-oldy)
    unit.x = x
    unit.y = y
    if unit.primary then
      love.mouse.setPosition(unit.screenx + mx,unit.screeny + my)
      --updating the real mouse position moves every mous, so to counter this we move every non-real mous in the opposite direction
      for _,cursor in ipairs(cursors) do
        if not cursor.primary then
          cursor.x = cursor.x - (x-oldx)
          cursor.y = cursor.y - (y-oldy)
          cursor.screenx = cursor.screenx - mx
          cursor.screeny = cursor.screeny - my
        end
      end
    else
      unit.screenx = unit.screenx + mx
      unit.screeny = unit.screeny + my
    end
  elseif (unit.fullname == "no1") and inBounds(x, y) then
    if rules_with["no1"] and rules_with["wurd"] and hasRule("no1", "be", "wurd") then
      should_parse_rules = true
    end
    local tileid = unit.x + unit.y * mapwidth
    local oldx = unit.x
    local oldy = unit.y
    unit.x = x
    unit.y = y
    local dest_tileid = unit.x + unit.y * mapwidth
    dest_empty = empties_by_tile[dest_tileid]
    dest_empty.x = oldx
    dest_empty.y = oldy
    dest_empty.dir = unit.dir
    empties_by_tile[tileid] = dest_empty
    empties_by_tile[dest_tileid] = unit
  else
    removeFromTable(unitsByTile(unit.x, unit.y), unit)
    if rules_with and thicc_units[unit] then
      removeFromTable(unitsByTile(unit.x+1,unit.y),unit)
      removeFromTable(unitsByTile(unit.x,unit.y+1),unit)
      removeFromTable(unitsByTile(unit.x+1,unit.y+1),unit)
    end

    -- putting portal check above same-position check to give portal effect through one-tile gap
    if portal and portal.is_portal and x - portal.x == dirs8[portal.dir][1] and y - portal.y == dirs8[portal.dir][2] and not instant then
      if unit.type == "txt" or rules_effecting_names[unit.name] or rules_effecting_names[unit.fullname] or (rules_with["no1"] and rules_with["wurd"] and hasRule("no1", "be", "wurd")) then
        should_parse_rules = true
      end
      if (not unit_tests) then
        portaling[unit] = portal
        -- set draw positions to portal offset to interprolate through portals
        unit.draw.x, unit.draw.y = portal.draw.x, portal.draw.y
        addTween(tween.new(0.1, unit.draw, {x = x, y = y}), "unit:pos:" .. unit.tempid)
        if portal.name == "smol" and unit.fullname ~= "babby" then
          addTween(tween.new(0.05, unit.draw, {scaley = 0.5}, "outQuint"), "unit:scaley:" .. unit.tempid, function()
            addTween(tween.new(0.05, unit.draw, {scaley = 1}, "inQuint"), "unit:scaley:" .. unit.tempid)
          end)
        end
        -- instantly change object's rotation, weirdness ensues otherwise
        unit.draw.rotation = (unit.rotatdir - 1) * 45
        tweens["unit:rotation:" .. unit.tempid] = nil
      end
    elseif (x ~= unit.x or y ~= unit.y) and not instant then
      if unit.type == "txt" or rules_effecting_names[unit.name] or rules_effecting_names[unit.fullname] or (rules_with and rules_with["no1"] and rules_with["wurd"] and hasRule("no1", "be", "wurd")) then
        should_parse_rules = true
      end
      if not unit_tests then
        if rules_with and not thicc_units[unit] and unit.draw.x == x and unit.draw.y == y then
          --'bump' effect to show movement failed
          unit.draw.x = (unit.x+x*2)/3
          unit.draw.y = (unit.y+y*2)/3
          addTween(tween.new(0.1, unit.draw, {x = x, y = y}), "unit:pos:" .. unit.tempid)
        elseif math.abs(x - unit.x) < 2 and math.abs(y - unit.y) < 2 then
          --linear interpolate to adjacent destination
          addTween(tween.new(0.1, unit.draw, {x = x, y = y}), "unit:pos:" .. unit.tempid)
        else
          --fade in, fade out effect
          addTween(tween.new(0.05, unit.draw, {scalex = 0}), "unit:scalex:pos:" .. unit.tempid, function()
            tweens["unit:rotation:" .. unit.tempid] = nil
            tweens["unit:pos:" .. unit.tempid] = nil
            unit.draw.x = x
            unit.draw.y = y
            unit.draw.rotation = (unit.rotatdir - 1) * 45
            addTween(tween.new(0.05, unit.draw, {scalex = 1}), "unit:scalex:" .. unit.tempid)
          end)
        end
      end
    elseif instant then
      unit.draw.x = x
      unit.draw.y = y
    end

    unit.x = x
    unit.y = y
    
    table.insert(unitsByTile(unit.x, unit.y), unit)
    if rules_with and thicc_units[unit] then
      for i=1,3 do
        if not table.has_value(unitsByTile(unit.x+i%2,unit.y+math.floor(i/2)),unit) then
          table.insert(unitsByTile(unit.x+i%2,unit.y+math.floor(i/2)),unit)
        end
      end
    end
  end

  if not instant then
    do_move_sound = true
  end
end

function updateDir(unit, dir, force)
  local result = true
  if not force and rules_with ~= nil then
    if hasProperty(unit, "noturn") then
      return false
    end
    if hasRule(unit, "ben't", dirs8_by_name[dir]) then
      result = false
    end
    for i=1,8 do
      if hasRule(unit, "ben't", "spin"..i) then
        if (dir == (unit.dir+i-1)%8+1) then result = false end
      end
      if hasProperty(unit, dirs8_by_name[i]) and dir ~= i then
        dir = i
        result = false
      end
    end
  end
  if unit.name == "mous" then
    unit.dir = dir
    return true
  end
  
  unit.dir = dir
  if (unit.rotate and not hasRule(unit,"ben't","rotatbl")) or (rules_with ~= nil and hasProperty(unit,"rotatbl")) then
    unit.rotatdir = dir
  end
  
  --Some units in rules_effecting_names are there because their direction matters (a portal or part of a parse-effecting look at/seen by condition).
  if rules_effecting_names[unit.fullname] then
    should_parse_rules = true
  end
  
  updateNameBasedOnDir(unit)
  
  if (not unit_tests) then
    unit.draw.rotation = unit.draw.rotation % 360
    local target_rot = (unit.rotatdir - 1) * 45
    if (unit.rotate or (rules_with ~= nil and hasProperty(unit,"rotatbl"))) and math.abs(unit.draw.rotation - target_rot) == 180 then
      -- flip "mirror" effect
      addTween(tween.new(0.05, unit.draw, {scalex = 0}), "unit:scalex:rot:" .. unit.tempid, function()
        unit.draw.rotation = target_rot
        tweens["unit:rotation:"..unit.tempid] = nil
        addTween(tween.new(0.05, unit.draw, {scalex = 1}), "unit:scalex:" .. unit.tempid)
      end)
    else
      -- smooth angle rotation
      if unit.draw.rotation - target_rot > 180 then
        target_rot = target_rot + 360
      elseif target_rot - unit.draw.rotation > 180 then
        target_rot = target_rot - 360
      end
      addTween(tween.new(0.1, unit.draw, {scalex = 1}), "unit:scalex:" .. unit.tempid)
      addTween(tween.new(0.1, unit.draw, {rotation = target_rot}), "unit:rotation:" .. unit.tempid)
    end
  end
  return true
end

function updateNameBasedOnDir(unit)
  if unit.fullname == "txt_mayb" then
    should_parse_rules = true
  elseif unit.fullname == "txt_direction" then
    unit.textname = dirs8_by_name[unit.dir]
    should_parse_rules = true
  elseif unit.fullname == "txt_spin" then
    unit.textname = "spin" .. tostring(unit.dir)
    should_parse_rules = true
  elseif unit.fullname == "letter_colon" then
    if unit.dir == 3 then
      unit.textname = ".."
    else
      unit.textname = ":"
    end
    should_parse_rules = true
  elseif unit.fullname == "letter_parenthesis" then
    if unit.dir == 1 or unit.dir == 2 or unit.dir == 3 then
      unit.textname = "("
    elseif unit.dir == 5 or unit.dir == 6 or unit.dir == 7 then
      unit.textname = ")"
    end
    should_parse_rules = true
  elseif unit.fullname == "letter_h" then
    if unit.rotatdir == 3 or unit.rotatdir == 7 then
      unit.textname = "i"
    else
      unit.textname = "h"
    end
  elseif unit.fullname == "letter_i" then
    if unit.rotatdir == 3 or unit.rotatdir == 7 then
      unit.textname = "h"
    else
      unit.textname = "i"
    end
  elseif unit.fullname == "letter_n" then
    if unit.rotatdir == 3 or unit.rotatdir == 7 then
      unit.textname = "z"
    else
      unit.textname = "n"
    end
  elseif unit.fullname == "letter_z" then
    if unit.rotatdir == 3 or unit.rotatdir == 7 then
      unit.textname = "n"
    else
      unit.textname = "z"
    end
  elseif unit.fullname == "letter_m" then
    if unit.rotatdir == 5 then
      unit.textname = "w"
    else
      unit.textname = "m"
    end
  elseif unit.fullname == "letter_w" then
    if unit.rotatdir == 5 then
      unit.textname = "m"
    else
      unit.textname = "w"
    end
  elseif unit.fullname == "letter_6" then
    if unit.rotatdir == 5 then
      unit.textname = "9"
    else
      unit.textname = "6"
    end
  elseif unit.fullname == "letter_9" then
    if unit.rotatdir == 5 then
      unit.textname = "6"
    else
      unit.textname = "9"
    end
  elseif unit.fullname == "letter_no" then
    if unit.rotatdir == 5 then
      unit.textname = "on"
    else
      unit.textname = "no"
    end
  elseif unit.fullname == "letter_>" then
    if unit.rotatdir == 5 then
      unit.textname = "<"
    elseif unit.rotatdir == 3 then
      unit.textname = "v"
    else
      unit.textname = ">"
    end
  end
end

function newUnitID(id)
  if id then
    max_unit_id = math.max(id, max_unit_id)
    return id
  else
    max_unit_id = max_unit_id + 1
    return max_unit_id
  end
end

function newTempID()
  max_temp_id = max_temp_id + 1
  return max_temp_id
end

function newMouseID()
  max_mouse_id = max_mouse_id - 1
  return max_mouse_id
end

function undoWin()
  if hasProperty(outerlvl, "noundo") then return end
  currently_winning = false
  music_fading = false
  win_size = 0
  win_sprite_override = {}
end

function doWin(result_, payload_)
  if not currently_winning then
    local result = result_ or "won"
    local payload = payload_
    if payload == nil then
      payload = true
    end
    if doing_past_turns then
      past_queued_wins[result] = payload
    elseif result == "won" and payload == false then
      if readSaveFile{"levels",level_filename,"won"} then
        playSound("unwin")
        writeSaveFile(false, {"levels",level_filename,"won"})
      end
    else
      won_this_session = true
      win_reason = result
      currently_winning = true
      music_fading = true
      win_size = 0
      playSound("win")
      if (not replay_playback) then
        writeSaveFile(payload, {"levels", level_filename, result})
        love.filesystem.createDirectory("levels")
        local to_save = replay_string
        local rng_cache_populated = false
        for _,__ in pairs(rng_cache) do
          rng_cache_populated = true
          break
        end
        if (rng_cache_populated) then
          to_save = to_save.."|"..love.data.encode("string", "base64", serpent.line(rng_cache))
        end
        if not RELEASE_BUILD and world_parent == "officialworlds" then
          official_replay_string = to_save
        else
          local dir = "levels/"
          if world_parent ~= "officialworlds" then dir = getWorldDir() .. "/" end
          love.filesystem.write(dir .. level_filename .. ".replay", to_save)
          print("Replay successfully saved to " .. dir .. level_filename .. ".replay")
        end
      end
    end
	end
end

function doXWX()
  writeSaveFile(nil,{"levels",level_filename,"seen"})
  writeSaveFile(nil,{"levels",level_filename,"won"})
  writeSaveFile(nil,{"levels",level_filename,"bonus"})
  writeSaveFile(nil,{"levels",level_filename,"transform"})
  escResult(true, true)
end
