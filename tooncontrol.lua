--[[

    Sync Domoticz sensors / switches with Toon in case the value is changed on the physical device.
    Updates
        Thermostat Sensor
        Temperature Sensor
        Scenes switch based on program set on Toon
        (Auto)program switch to value set on Toon
        Program information text to value set on Toon

Van: https://www.domoticz.com/forum/viewtopic.php?f=59&t=26662
    ]] --

local toonResponse  = "toonResponse"
local ResponseOK    = "OK_toon_Response"
local scriptVersion = "version 0.2"
return {
                on  =   { timer         = { "every minute"      },
                          devices       = { "Toon Thermostaat","Toon Scenes"  },
                          httpResponses = { toonResponse , ResponseOK      }},

           logging  =   {
                            level       =       domoticz.LOG_INFO,
                            -- level       =       domoticz.LOG_DEBUG,
                            marker      =       scriptVersion .. " Toon"
                        },

               data =   {
                            lastActive    = { initial = 0     },
                            isActive      = { initial = false },
                            blockSetPoint = { initial = false },   -- Bug in TimedCommands (silent() does not work in updateSetPoint
                        },

    execute = function(dz, item)
        local now = os.time(os.date('*t'))                  -- seconds since 1/1/1970 00:00:01

        local function logWrite(str,level)
            dz.log(tostring(str),level or dz.LOG_DEBUG)
        end

        local function sendURL(url,callback)
            local toonIP = dz.variables("UV_ToonIP").value
            local url    = "http://" .. toonIP .. url
            dz.openURL({
                            url = url,
                            method = "GET",
                            callback = callback
                      })
        end

        local function setSetPoint(device,setPoint) -- update setPoint
            if device.setPoint ~= setPoint then
                logWrite("Updating thermostat sensor to new set point: " .. setPoint )
                device.updateSetPoint(setPoint)
            else
                dz.data.blockSetPoint = false
            end
        end

        local function setSelector(device,state,str) -- update selector
            if device.level ~= state and device.lastUpdate.secondsAgo > 59 then
                logWrite("Updating the " .. device.name .. " level to " .. str .. " (" .. state ..  ")")
                device.switchSelector(state).silent()
            end
        end

        local function setTemperature(device,temperature) -- Update temperature sensor
            if device.temperature ~= temperature then
                logWrite("Updating the temperature sensor to: " .. temperature)
                device.updateTemperature(temperature).silent()
            end
        end

        local function setText(device,text)    -- Update text sensor
            if device.text ~= text then
                logWrite("Updating " .. device.name .. " to: " .. text)
                device.updateText(text)
            end
        end

        local function setSetPointInfo(device,nextTime,setPoint)
            if nextTime == 0 or setPoint == 0 then
                newText = "Op " .. setPoint .. "▒"
            else
                newText = "Om " ..os.date("%H:%M", nextTime).. " naar " .. setPoint .. "▒"
            end
            setText(device,newText)
        end

        local function setSceneState(device,state)
            local states       = { 50,40,30,20,10}  -- Manual, Comfort, Home, Sleep , Away
            local stateStrings = { "Manual", "Comfort", "Home", "Sleep" , "Away"}
            local newState     = states[state + 2]
            local stateString  = stateStrings[state + 2]
            setSelector(device,newState,stateString)
        end

        local function setProgramState(device,state)
            local states       = { 10,20,30 }  -- No, Yes, Temporary
            local stateStrings = { "No", "Yes", "Temporary" }
            local newState     = states[state + 1]
            local stateString  = stateStrings[state + 1]
            setSelector(device,newState,stateString)
        end

        local function setBurnerState(device,state)
            local states       = { 0,10,20 }  -- Off, CV, WW
            local stateStrings = { "Off", "CV", "WW" }
            local newState     = states[state + 1]
            local stateString  = stateStrings[state + 1]
            setSelector(device,newState,stateString)
        end

        local function updateDevices(rt)
            local toonThermostat            = dz.devices(dz.variables("UV_ToonThermostatSensorName").value)           -- Sensor showing current setpoint
            local toonTemperature           = dz.devices(dz.variables("UV_ToonTemperatureSensorName").value)          -- Sensor showing current room temperature
            local toonScenes                = dz.devices(dz.variables("UV_ToonScenesSensorName").value)               -- Sensor showing current program
            local toonAutoProgram           = dz.devices(dz.variables("UV_ToonAutoProgramSensorName").value)          -- Sensor showing current auto program status
            local toonProgramInformation    = dz.devices(dz.variables("UV_ToonProgramInformationSensorName").value)   -- Sensor showing displaying program information status
            local toonBurner                = dz.devices(dz.variables("UV_ToonBurnerInfo").value)                                 -- Sensor showing current CV information status
            -- local toonModulation

            setSetPoint     (toonThermostat,          dz.utils.round(rt.currentSetpoint / 100,1          ))
            setTemperature  (toonTemperature,         dz.utils.round(rt.currentTemp / 100,1              ))
            setSceneState   (toonScenes,              rt.activeState                                      )  -- "activeState":"-1" ==> 50
            setProgramState (toonAutoProgram,         rt.programState                                     )  -- "programState":"0" ==> 10
                        setBurnerState  (toonBurner,  rt.burnerInfo                                       )  -- "burnerInfo":"0" ==> 0
            setText         (toonProgramInformation,  dz.utils.round(rt.nextTime,rt.nextSetpoint / 100,1 ))
        end

        local function procesToonResponse()
            logWrite(tostring(item.data))
            return dz.utils.fromJSON(item.data)
        end

        local function sendSetPoint(newSetPoint)

            logWrite("In function sendSetPoint; " .. item.name .. " wants to set setPoint to " .. newSetPoint)
            local calculatedSetPoint = newSetPoint * 100
            local urlString = "/happ_thermstat?action=setSetpoint&Setpoint=" .. calculatedSetPoint
            if not dz.data.blockSetPoint then
                sendURL(urlString, ResponseOK )
                logWrite("Toon setPoint send using " .. urlString)
            else
                logWrite("Toon setPoint not send ; unblocking now ")
                dz.data.blockSetPoint = false
            end
        end

        local function sendScene()
            local newstate
            logWrite("In function sendScene; " .. item.name .. "; level " .. item.level .. " ==>> " .. item.levelName)

            if item.level ==  0 then  -- Off
                sendSetPoint(60)
                return
            end

            if      item.level == 10 then newState = 3       -- Away
            elseif  item.level == 20 then newState = 2       -- Sleep
            elseif  item.level == 30 then newState = 1       -- Home
            elseif  item.level == 40 then newState = 0       -- Comfort
            else                          newState = -1      -- Invalid
            end

            local urlString = "/happ_thermstat?action=changeSchemeState&state=2&temperatureState=" .. newState
            sendURL(urlString, ResponseOK )
            logWrite("Toon SchemeState send using " .. urlString)
        end

        local function getInfo()
            sendURL("/happ_thermstat?action=getThermostatInfo",toonResponse)
        end

        -- Check for conflicts between timer and set Toon
        local function setActive(state)
            if state then
                logWrite("Triggered by device. Setting active")
                dz.data.isActive    = true
                dz.data.lastActive  = now
            else
                dz.data.isActive    = false
                logWrite("Answer from Toon. Unset active")
            end
        end

        local function isFree()
            return (( dz.data.lastActive + 90 ) < now ) or ( not dz.data.isActive )
        end

        local function writeStatus(origin)
            logWrite(origin .. "isFree:               " .. tostring(isFree()))
            logWrite(origin .. "lastActive:           " .. os.date("%X",dz.data.lastActive))
            logWrite(origin .. "blockSetPoint:        " .. tostring(dz.data.blockSetPoint))
        end

        -- main program
        writeStatus("-- start -- ")
        if item.isDevice then                               -- triggered by selector or setPoint
            if item.name == "Toon Scenes" then
                sendScene()
                setActive(true)
            else
                sendSetPoint(item.setPoint)
                setActive(true)
            end
        elseif item.isTimer and isFree() then                    -- triggered by timer
                dz.data.blockSetPoint = true
                getInfo()
        elseif item.isHTTPResponse then                              -- Triggered by Toon response
            if item.trigger == toonResponse then                 -- return from getInfo()
                if item.ok and isFree() then                     -- statusCode == 2xx
                    updateDevices(procesToonResponse())
                elseif isFree() then
                    logWrite("Toon did not return valid data. Please check what went wrong. Error code: " .. item.statusCode or 999  ,dz.LOG_ERROR)
                    logWrite("Invalid data: " .. tostring(item.data))
                else
                    logWrite("Toon is busy dealing with sendScene or sendSetPoint")
                end
            else
                logWrite("returned from sendScene or sendSetPoint: " .. tostring(item.data))
                setActive(false)
            end
        else
            logWrite("This should never happen")
        end
        writeStatus("-- end -- ")
    end
}
