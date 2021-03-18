local PLUGIN_NAME     = 'homebridge2openluup'
--local PLUGIN_SID      = 'urn:ctrlable-com:serviceId:'..PLUGIN_NAME..'1'
local PLUGIN_VERSION  = '0.1'
local THIS_LUL_DEVICE = nil

local g_username = ""
local g_password = ""
local access_token = ""
local token_type = ""
local index = 0
local ipAddress = nil
local ipPort = nil
local m_Connected = false

local SID = {
        ["HOMEBRIDGE"]      = "urn:ctrlable-com:serviceId:"..PLUGIN_NAME.."1",
        ["SW_POWER"]         = "urn:upnp-org:serviceId:SwitchPower1",
        ["SW_GATE"]         = "urn:upnp-org:serviceId:SwitchPower1",
        ["DIMMER"]           = "urn:upnp-org:serviceId:Dimming1",
        ["BLINDS"]           = "urn:upnp-org:serviceId:WindowCovering1",
        ["SHADEGRP"]         = "urn:upnp-org:serviceId:WindowCovering1",
        ["KEYPAD"]           = "urn:upnp-org:serviceId:LutronKeypad1",
        ["AREA"]             = "urn:micasaverde-com:serviceId:SecuritySensor1",
        ["LOCK"]             = "urn:micasaverde-com:serviceId:DoorLock1",
        ["TH_USER_MODE"]     = "urn:upnp-org:serviceId:HVAC_UserOperatingMode1", 
        ["TH_USER_STATE"]    = "urn:micasaverde-com:serviceId:HVAC_OperatingState1",    
        ["TH_FAN_MODE"]      = "urn:upnp-org:serviceId:HVAC_FanOperatingMode1",
        ["TH_FAN_SPEED"]     = "urn:upnp-org:serviceId:FanSpeed1",
        ["TH_TEMP_SET"]      = "urn:upnp-org:serviceId:TemperatureSetpoint1",
        ["TH_TEMP_SET_COOL"] = "urn:upnp-org:serviceId:TemperatureSetpoint1_Cool",
        ["TH_TEMP_SET_HEAT"] = "urn:upnp-org:serviceId:TemperatureSetpoint1_Heat",
        ["TH_TEMP_SENSOR"]   = "urn:upnp-org:serviceId:TemperatureSensor1"        
}
local DEVTYPE = {
        ["SW_POWER"]                = "urn:schemas-upnp-org:device:BinaryLight:1",
        ["SW_GATE"]                = "urn:schemas-upnp-org:device:BinaryLight:1",
        ["DIMMER"]                  = "urn:schemas-upnp-org:device:DimmableLight:1",
        ["BLINDS"]                  = "urn:schemas-micasaverde-com:device:WindowCovering:1",
        ["SHADEGRP"]                = "urn:schemas-micasaverde-com:device:WindowCovering:1",
        ["KEYPAD"]                  = "urn:schemas-micasaverde-com:device:LutronKeypad:1",
        ["AREA"]                    = "urn:schemas-micasaverde-com:device:MotionSensor:1",
        ["LOCK"]                    = "urn:schemas-micasaverde-com:device:DoorLock:1",
        ["THERMOSTAT"]              = "urn:schemas-upnp-org:device:HVAC_ZoneThermostat:1"
}

local g_childDevices = {
    -- .id       -> vera id
    -- .integrationId -> lutron internal id
    -- .devType -> device type (dimmer, blinds , binary light or keypad)
    -- .fadeTime 
    -- .componentNumber = {} -> only for keypads
}

local lxp = require('lxp')
local json = require('dkjson')
--local json = require('json')
local socket = require('socket')
local http   = require('socket.http')
local ltn12  = require('ltn12')

local DEBUG_MODE = true

local function debug(textParm, logLevel)
    if DEBUG_MODE then
        local text = ''
        local theType = type(textParm)
        if (theType == 'string') then
            text = textParm
        else
            text = 'type = '..theType..', value = '..tostring(textParm)
        end
        luup.log(PLUGIN_NAME..' debug: '..text,50)

    elseif (logLevel) then
        local text = ''
        if (type(textParm) == 'string') then text = textParm end
        luup.log(PLUGIN_NAME..' debug: '..text, logLevel)
    end
end

function round(number)
    if math.floor(number) + 0.5 <= number then
        return math.floor(number) + 1
    else 
        return math.floor(number)
    end
end

function round_dec(number)
   local precision = 1
   local fmtStr = string.format('%%0.%sf',precision)
   number = string.format(fmtStr,number)
   return number
end

function round_dec_precision(number, precision)
   local fmtStr = string.format('%%0.%sf',precision)
   number = string.format(fmtStr,number)
   return number
end


function round_temp(number) 
    local n = tonumber(number)

    local minNumber = math.floor(n) -- (The variable will be 1)

    if n < (minNumber + .25) then -- if the number is smaller than 1.25 (min number + .25)
        local RoundedNumber = math.floor(n) -- the rounded number is 1
        return RoundedNumber
    elseif n >= (minNumber + .75) then -- if the number is higher than 1.75 (minnumber + .75)
        local RoundedNumber = math.floor(n) + 1 --the rounded number is 2
        return RoundedNumber
    end

    if n >= (minNumber + .25) then
        if n < (minNumber + .75) then
            -- if the number is between 1.25 and 1.75
            local RoundedNumber = math.floor(n) + .5 -- the rounded number is 1.5
            return RoundedNumber
        end
    end
end

function temp_celsius(number)
    return (number - 32.0) * 5.0/9.0
end

function temp_fahrenheit(number)
    return number * (9.0/5.0) + 32.0
end

local function getInfo(device)
        --local flagError = true
        g_username = luup.devices[device].user or ""
        g_password = luup.devices[device].pass or ""
        local period = luup.variable_get(SID["HOMEBRIDGE"],"pollPeriod", device) or ""
        if g_username == "" or g_password == "" or g_username == "default" or g_password == "default" then
                luup.attr_set("username","default",device)
                luup.attr_set("password","default",device)
                luup.log( "(Homebridge PLugin)::(getInfo) : ERROR : Username or Password field cannot be blank or default!" )
                --flagError = false
        end

        local trash
        ipAddress, trash, ipPort = string.match(luup.devices[THIS_LUL_DEVICE].ip, "^([%w%.%-]+)(:?(%d-))$")
        if ipAddress and ipAddress ~= "" then
                if ipPort==nil or ipPort == "" then
                        ipPort = "8581"
                end
                --flagConnect = true
        else
                log("(Homebridge PLugin)::(getInfo) : ERROR : Insert IP address!")
                --flagError = false
        end
        --return flagError
end

local function updateVariable(varK, varV, sid, id)
    if (sid == nil) then sid = SID["HOMEBRIDGE"]      end
    if (id  == nil) then  id = THIS_LUL_DEVICE end

    if ((varK == nil) or (varV == nil)) then
        luup.log(PLUGIN_NAME..' debug: '..'Error: updateVariable was supplied with a nil value', 1)
        return
    end

    local newValue = tostring(varV)
    debug(newValue..' --> '..varK)

    local currentValue = luup.variable_get(sid, varK, id)
    if ((currentValue ~= newValue) or (currentValue == nil)) then
        luup.variable_set(sid, varK, newValue, id)
    end
end

local function homebridgeLogin()
    http.TIMEOUT = 1
    --local login_payload = [[ {"username":"..admin","password":"admin","otp":"ctrlable"} ]]
    local request_body =  "{\"username\":\""..g_username.."\",\"password\":\""..g_password.."\",\"otp\":\"ctrlable\"}"
    local response_body = {}

    -- site not found: r is nil, c is the error status eg (as a string) 'No route to host' and h is nil
    -- site is found:  r is 1, c is the return status (as a number) and h are the returned headers in a table variable
    local r, c, h = http.request {
          url     = 'http://'..ipAddress..':'..ipPort..'/api/auth/login',
          method  = 'POST',
          headers = {
            ['Content-Type']   = 'application/json',
            ['Content-Length'] = string.len(request_body)
          },
          source = ltn12.source.string(request_body),
          sink   = ltn12.sink.table(response_body)
    }
    debug('URL request result: r = '..tostring(r))
    debug('URL request result: c = '..tostring(c))
    debug('URL request result: h = '..tostring(h))
    debug('response_body 1 = '..response_body[1])



    local page = ''
    if (r == nil) then return false, page end

    if ((c == 201) and (type(response_body) == 'table')) then


        page = table.concat(response_body)
        --local response_body_parsed = json.decode(response_body[1])
        local response_body_parsed = json.decode(response_body[1])

        debug('Returned web page data is : '..page)


        access_token = response_body_parsed["access_token"]
        token_type = response_body_parsed["token_type"]
        if (access_token == nil) then
            luup.log(PLUGIN_NAME..' debug: Error - this command is invalid: '..request_body, 1)
            return false, page
        end

        updateVariable('access_token', access_token)
        updateVariable('token_type', token_type)
        debug('response_body_parse access_token = '..response_body_parsed["access_token"])
        debug('response_body_parse token_type = '..response_body_parsed["token_type"])
        debug('response_body_parse expires_in = '..response_body_parsed["expires_in"])

        updateVariable('Connected', '1')

        return true, page
    end

    if (c == 400) then
        luup.log(PLUGIN_NAME..' debug: HTTP 400 Bad Request: JSON parse error', 1)
        updateVariable('Connected', '0')

        return false, page
    end

    return false, page


end

local function homebridgeGetDevices()
    http.TIMEOUT = 5
    local response_body = {}
    local request_body = ""..token_type.." "..access_token..""

--Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VybmFtZSI6ImFkbWluIiwibmFtZSI6IkFkbWluaXN0cmF0b3IiLCJhZG1pbiI6dHJ1ZSwiaW5zdGFuY2VJZCI6IjcxMTZjMjI5N2RmNDMwNjUyNjg3MDA5MTE4YTMxNDk4ODU0NWU2ODNlMzg4YjlkMDgxNDY2ZGEyZDQ3ZjZkMWMiLCJpYXQiOjE2MDk3NjE3NjMsImV4cCI6MTYwOTc5MDU2M30.6pNrLQLT7XRWMuUyfnX7kUyhaUO3L-0BsHW0j-oy2iA"

    local r, c, h = http.request {
          url     = 'http://'..ipAddress..':'..ipPort..'/api/accessories',
          method  = 'GET',
          headers = {
            ['Content-Type']   = 'application/json',
            ['Content-Length'] = string.len(request_body),
            ["Authorization"] = request_body
          },
          source = ltn12.source.string(request_body),
          sink   = ltn12.sink.table(response_body)
    }
    debug('URL request result: r = '..tostring(r))
    debug('URL request result: c = '..tostring(c))
    debug('URL request result: h = '..tostring(h))
    --debug('response_body 1 = '..response_body[1])
        local concat_response_body = table.concat(response_body)
        local response_body_decode = json.decode(concat_response_body)

        local response_body_parsed = json.decode(response_body[1])

        --debug('response_body_parse serviceName = '..response_body_parsed[1]["serviceName"])

        for i in pairs(response_body_decode) do           
            debug('homebridgeGetDevices' .. i ..' = uniqueId '..response_body_decode[i]["uniqueId"] .. ' Type : ' .. response_body_decode[i]["type"] .. ' serviceName : ' .. response_body_decode[i]["serviceName"])
        end

end

local function homebridgeGetDeviceValues(deviceId,deviceType,uniqueid)
    local g_uniqueId = uniqueid
    local g_deviceId = deviceId
    local g_deviceType = deviceType

    http.TIMEOUT = 5
    local response_body2 = {}
    local request_body = ""..token_type.." "..access_token..""
    local g_tempformat = luup.attr_get "TemperatureFormat"
    
    local evalFahr = false

    if g_tempformat == "F" then
        evalFahr = true
    end


    local r, c, h = http.request {
          url     = 'http://'..ipAddress..':'..ipPort..'/api/accessories/'..g_uniqueId,
          method  = 'GET',
          headers = {
            ['Content-Type']   = 'application/json',
            ['Content-Length'] = string.len(request_body),
            ["Authorization"] = request_body
          },
          source = ltn12.source.string(request_body),
          sink   = ltn12.sink.table(response_body2)
    }
    local concat_response_body = table.concat(response_body2)
    debug('URL request result: r = '..tostring(r))
    debug('URL request result: c = '..tostring(c))
    debug('URL request result: h = '..tostring(h))
    debug('concat_response_body 1 = '..concat_response_body)

        local response_body_decode = json.decode(concat_response_body)

        if g_deviceType == "THERMOSTAT" then
                debug('Engine Global Temperature Unit = '..g_tempformat)
                local thermoType = response_body_decode["type"] or ""
                local thermoManu = response_body_decode["accessoryInformation"]["Manufacturer"] or ""
                local thermoModel = response_body_decode["accessoryInformation"]["Model"] or ""

                debug('Homebridge Device Type = '..thermoType)

                --if (g_tempformat == "F") then
       
                    local CoolingThresholdTemperature = response_body_decode["values"]["CoolingThresholdTemperature"] or ""
                    local HeatingThresholdTemperature = response_body_decode["values"]["HeatingThresholdTemperature"] or ""
                    local onoffstatus = response_body_decode["values"]["StatusActive"] or ""
                    local processed_cooling_temp = ""
                    local processed_heating_temp = ""

                    --local processed_current_temp = round_temp(temp_fahrenheit(response_body_decode["values"]["CurrentTemperature"]))
                    local processed_current_temp = (evalFahr and round_temp(temp_fahrenheit(response_body_decode["values"]["CurrentTemperature"])) or round_temp(response_body_decode["values"]["CurrentTemperature"]))

                    if CoolingThresholdTemperature ~= "" then  -- FOR ECOBEE3 HOMEBRIDGE PLUGIN 
                        --processed_cooling_temp = round_temp(temp_fahrenheit(response_body_decode["values"]["CoolingThresholdTemperature"]))
                        processed_cooling_temp = (evalFahr and round_temp(temp_fahrenheit(response_body_decode["values"]["CoolingThresholdTemperature"])) or round_temp(response_body_decode["values"]["CoolingThresholdTemperature"]))
                        debug("NOT Ecobee Processed Cooling Temp CoolingThresholdTemperature: " ..processed_cooling_temp)
                    else
                        --processed_cooling_temp = round_temp(temp_fahrenheit(response_body_decode["values"]["TargetTemperature"]))
                        processed_cooling_temp = (evalFahr and round_temp(temp_fahrenheit(response_body_decode["values"]["TargetTemperature"])) or round_temp(response_body_decode["values"]["TargetTemperature"]))
                        debug("IS Ecobee Processed Cooling Temp TargetTemperature: " ..processed_cooling_temp)
                    end

                    if HeatingThresholdTemperature ~= "" then -- FOR ECOBEE3 HOMEBRIDGE PLUGIN 
                        --processed_heating_temp = round_temp(temp_fahrenheit(response_body_decode["values"]["HeatingThresholdTemperature"]))
                        processed_heating_temp = (evalFahr and round_temp(temp_fahrenheit(response_body_decode["values"]["HeatingThresholdTemperature"])) or round_temp(response_body_decode["values"]["HeatingThresholdTemperature"]))
                    else
                        --processed_heating_temp = round_temp(temp_fahrenheit(response_body_decode["values"]["TargetTemperature"]))
                        processed_heating_temp = (evalFahr and round_temp(temp_fahrenheit(response_body_decode["values"]["TargetTemperature"])) or round_temp(response_body_decode["values"]["TargetTemperature"]))
                    end                        

                    if thermoType == "Thermostat" then -- Homebredige devType Thermostat
                        --processed_target_temp = temp_fahrenheit(round_temp(response_body_decode["values"]["TargetTemperature"]))
                        processed_target_temp = (evalFahr and temp_fahrenheit(round_temp(response_body_decode["values"]["TargetTemperature"])) or round_temp(response_body_decode["values"]["TargetTemperature"]))
                        
                        if onoffstatus == "" then -- FOR ECOBEE3 HOMEBRIDGE PLUGIN
                            if response_body_decode["values"]["TargetHeatingCoolingState"] == 0 and response_body_decode["values"]["CurrentHeatingCoolingState"] == 0 then
                                 onoffstatus = 0
                            else
                                onoffstatus = 1
                            end
                        else
                            onoffstatus = response_body_decode["values"]["StatusActive"]
                        end

                        luup.variable_set(SID["TH_USER_MODE"],"Type", "Thermostat" ,g_deviceId)
                        luup.variable_set(SID["TH_USER_MODE"],"Manufacturer", thermoManu ,g_deviceId)
                        luup.variable_set(SID["TH_USER_MODE"],"Model", thermoModel ,g_deviceId)

                        debug('The Homebride device is a Thermostat w target temp = '..processed_target_temp ..' Active Value: ' .. onoffstatus)
                        luup.variable_set(SID["TH_TEMP_SET"],"CurrentSetpoint", processed_cooling_temp, g_deviceId)
                        luup.variable_set(SID["SW_POWER"],"Status", onoffstatus ,g_deviceId)

                        if response_body_decode["values"]["TargetHeatingCoolingState"] == 2 then
                            luup.variable_set(SID["TH_USER_MODE"],"ModeStatus", "CoolOn" ,g_deviceId)
                        elseif response_body_decode["values"]["TargetHeatingCoolingState"] == 1 then
                            luup.variable_set(SID["TH_USER_MODE"],"ModeStatus", "HeatOn" ,g_deviceId)
                        elseif response_body_decode["values"]["TargetHeatingCoolingState"] == 3 then
                            luup.variable_set(SID["TH_USER_MODE"],"ModeStatus", "AutoChangeOver" ,g_deviceId)
                        else    
                            luup.variable_set(SID["TH_USER_MODE"],"ModeStatus", "Off" ,g_deviceId)
                        end 

                    elseif thermoType == "HeaterCooler" then  -- Homebredige devType Heater Cooler
                        --local processed_target_temp = temp_fahrenheit(round_temp(response_body_decode["values"]["TargetHeaterCoolerState"]))
                        local processed_target_temp = (evalFahr and temp_fahrenheit(round_temp(response_body_decode["values"]["TargetHeaterCoolerState"])) or round_temp(response_body_decode["values"]["TargetHeaterCoolerState"]))
                        local onoffstatus = response_body_decode["values"]["Active"]
                        luup.variable_set(SID["TH_USER_MODE"],"Type", "HeaterCooler" ,g_deviceId)
                        luup.variable_set(SID["TH_USER_MODE"],"Manufacturer", thermoManu ,g_deviceId)
                        luup.variable_set(SID["TH_USER_MODE"],"Model", thermoModel ,g_deviceId)

                        debug('The Homebride device is a Heater cooler w target temp = '..processed_target_temp ..' Active Value: '.. onoffstatus ..' TargetHeaterCoolerState: '.. response_body_decode["values"]["TargetHeaterCoolerState"])
                        luup.variable_set(SID["TH_TEMP_SET"],"CurrentSetpoint", processed_cooling_temp, g_deviceId)
                        luup.variable_set(SID["SW_POWER"],"Status", response_body_decode["values"]["Active"] ,g_deviceId)

                        if response_body_decode["values"]["TargetHeaterCoolerState"] == 2 and response_body_decode["values"]["Active"] == 1 then
                            luup.variable_set(SID["TH_USER_MODE"],"ModeStatus", "CoolOn" ,g_deviceId)
                        elseif response_body_decode["values"]["TargetHeaterCoolerState"] == 1 and response_body_decode["values"]["Active"] == 1 then
                            luup.variable_set(SID["TH_USER_MODE"],"ModeStatus", "HeatOn" ,g_deviceId)
                        elseif response_body_decode["values"]["TargetHeaterCoolerState"] == 0 and response_body_decode["values"]["Active"] == 1 then
                            luup.variable_set(SID["TH_USER_MODE"],"ModeStatus", "AutoChangeOver" ,g_deviceId)
                        else    
                            luup.variable_set(SID["TH_USER_MODE"],"ModeStatus", "Off" ,g_deviceId)
                        end   
                    end
                --end

             debug("processed_cooling_temp : " .. processed_cooling_temp )   
             luup.variable_set(SID["TH_TEMP_SENSOR"],"CurrentTemperature", processed_current_temp, g_deviceId)
             luup.variable_set(SID["TH_TEMP_SET_COOL"],"CurrentSetpoint", processed_cooling_temp, g_deviceId)
             luup.variable_set(SID["TH_TEMP_SET_HEAT"],"CurrentSetpoint", processed_heating_temp, g_deviceId)

            --debug('homebridgeGetDeviceValues response_body_decode serviceName = '..response_body_decode.uuid)

        end

        if g_deviceType == "SW_POWER" then

                local onoffstatus = response_body_decode["values"]["On"] or ""
                --local brigtnesslevel = response_body_decode["values"]["Brightness"] or ""

                luup.variable_set(SID["SW_POWER"],"Status", onoffstatus ,g_deviceId)
                --luup.variable_set(SID["DIMMER"],"LoadLevelTarget", brigtnesslevel ,g_deviceId)

        end

        if g_deviceType == "SW_GATE" then

                local onoffstatus = response_body_decode["values"]["On"] or ""
                --local brigtnesslevel = response_body_decode["values"]["Brightness"] or ""

                luup.variable_set(SID["SW_GATE"],"Status", onoffstatus ,g_deviceId)
                --luup.variable_set(SID["DIMMER"],"LoadLevelTarget", brigtnesslevel ,g_deviceId)

        end

        if g_deviceType == "DIMMER" then

                local onoffstatus = response_body_decode["values"]["On"] or ""
                local brigtnesslevel = response_body_decode["values"]["Brightness"] or ""

                luup.variable_set(SID["SW_POWER"],"Status", onoffstatus ,g_deviceId)
                luup.variable_set(SID["DIMMER"],"LoadLevelTarget", brigtnesslevel ,g_deviceId)

        end

        if g_deviceType == "AREA" then

                local sensorstatus = response_body_decode["values"]["MotionDetected"] or ""
                luup.variable_set(SID["AREA"],"Tripped", sensorstatus ,g_deviceId)

        end

        if g_deviceType == "LOCK" then

                local lockcurrentstate = response_body_decode["values"]["LockCurrentState"] or ""
                local locktargetstate = response_body_decode["values"]["LockTargetState"] or ""
                luup.variable_set(SID["LOCK"],"Status", lockcurrentstate ,g_deviceId)
                luup.variable_set(SID["LOCK"],"Target", locktargetstate ,g_deviceId)

        end
end

local function homebridgePutDevice(uniqueid, characteristicType, value)
    local g_uniqueId = uniqueid
    local g_characteristicType = characteristicType
    local g_value = value
    local request_body
    debug('Homebridge Put device VALUE = '..g_value)

    http.TIMEOUT = 1
    --local login_payload = [[ {"username":"..admin","password":"admin","otp":"ctrlable"} ]]
    local request_body_auth = ""..token_type.." "..access_token..""
    if g_characteristicType == "Brightness" then
        request_body =  "{\"characteristicType\":\""..g_characteristicType.."\",\"value\":\ " .. g_value .. "}"
        debug('request_body for numbers = '..request_body)
    else
        request_body =  "{\"characteristicType\":\""..g_characteristicType.."\",\"value\":\""..g_value.."\"}"
        debug('request_body for everything else = '..request_body)
    end
    local response_body = {}
    debug('PUT Auth = '..request_body_auth)
    debug('PUT Request Body = '..request_body)
    debug('PUT Request Length = ' .. string.len(request_body))

    local r, c, h = http.request {
          url     = 'http://'..ipAddress..':'..ipPort..'/api/accessories/'.. g_uniqueId ,
          method  = 'PUT',
          headers = {
            ['Content-Type']   = 'application/json',
            ["Authorization"] = request_body_auth,
            ['Content-Length'] = string.len(request_body)
          },
          source = ltn12.source.string(request_body),
          sink   = ltn12.sink.table(response_body)
    }
    debug('URL request result: r = '..tostring(r))
    debug('URL request result: c = '..tostring(c))
    debug('URL request result: h = '..tostring(h))
    debug('PUT Access Token = '..access_token)

    debug('response_body PUT 1 = '..response_body[1])



    local page = ''
    if (r == nil) then return false, page end

    if ((c == 201) and (type(response_body) == 'table')) then


        page = table.concat(response_body)
        --local response_body_parsed = json.decode(response_body[1])
        local response_body_parsed = json.decode(response_body[1])

        debug('Returned web page data is : '..page)


        --updateVariable('access_token', access_token)
        --updateVariable('token_type', token_type)
        debug('response_body_parse access_token = '..response_body_parsed["access_token"])
        debug('response_body_parse token_type = '..response_body_parsed["token_type"])
        debug('response_body_parse expires_in = '..response_body_parsed["expires_in"])

        return true, page
    end

    if (c == 400) then
        luup.log(PLUGIN_NAME..' debug: HTTP 400 Bad Request: JSON parse error', 1)
        return false, page
    end

    return false, page
end

local function SplitString (str, delimiter)
    --delimiter = delimiter or "%s+"
    delimiter = delimiter
    local result = {}
    local from = 1
    local delimFrom, delimTo = str:find( delimiter, from )
    while delimFrom do
        table.insert( result, str:sub( from, delimFrom-1 ) )
        from = delimTo + 1
        delimFrom, delimTo = str:find( delimiter, from )
    end
    table.insert( result, str:sub( from ) )
    return result
end

local function getDevices(device)
    local dev = luup.variable_get(SID["HOMEBRIDGE"],"DeviceList",device) or ""

    debug('DeviceList Values = '..dev)

    if dev == "" then
        luup.variable_set(SID["HOMEBRIDGE"],"DeviceList","",THIS_LUL_DEVICE)
        return false        
    else
        -- Parse the DeviceData variable.
        local deviceList = SplitString( dev, ';' )
        for k,v in pairs(deviceList) do
            local typedev = v:sub(1,1)
            --for val in v:gmatch("(%w+)") do
            for val in v:gmatch("([a-z0-9]+)") do
                index = index + 1
                g_childDevices[index] = {}
                g_childDevices[index].id = -1 
                if typedev == "D" then
                    g_childDevices[index].integrationId = val
                    g_childDevices[index].devType = "DIMMER"
                elseif typedev == "B" then
                    g_childDevices[index].integrationId = val
                    g_childDevices[index].devType = "BLINDS"
                elseif typedev == "S" then
                    g_childDevices[index].integrationId = val
                    g_childDevices[index].devType = "SW_POWER"
                elseif typedev == "G" then
                    g_childDevices[index].integrationId = val
                    g_childDevices[index].devType = "SW_GATE"
                elseif typedev == "L" then
                    g_childDevices[index].integrationId = val
                    g_childDevices[index].devType = "LOCK"
                elseif typedev == "T" then
                    g_childDevices[index].integrationId = val
                    g_childDevices[index].devType = "THERMOSTAT"
                 elseif typedev == "A" then
                    g_childDevices[index].integrationId = val
                    g_childDevices[index].devType = "AREA"
                else
                    log("(Homebridge PLugin)::(getDevices) : ERROR : DeviceList spelling error found")  
                end
            end
        end
    end
    return true
end

local function appendDevices(device)
    local ptr = luup.chdev.start(device)
    local index = 0
    for key, value in pairs(g_childDevices) do
        if value.devType == "DIMMER" then
            luup.chdev.append(device,ptr, value.integrationId,"DIMMER_" .. value.integrationId,DEVTYPE[value.devType],"D_DimmableLight1.xml","","",false)
        elseif value.devType == "BLINDS" then
            luup.chdev.append(device,ptr, value.integrationId,"BLINDS_" .. value.integrationId,DEVTYPE[value.devType],"D_WindowCovering1.xml","","",false)
        elseif value.devType == "SW_POWER" then
            luup.chdev.append(device,ptr, value.integrationId,"BINARY_LIGHT_" .. value.integrationId,DEVTYPE[value.devType],"D_BinaryLight1.xml","","",false)
        elseif value.devType == "SW_GATE" then
            luup.chdev.append(device,ptr, value.integrationId,"GATE_" .. value.integrationId,DEVTYPE[value.devType],"D_GarageDoor1.xml","","",false)
        elseif value.devType == "LOCK" then
            luup.chdev.append(device,ptr, value.integrationId,"LOCK_" .. value.integrationId,DEVTYPE[value.devType],"D_DoorLock1.xml","","",false)
        elseif value.devType == "THERMOSTAT" then
            luup.chdev.append(device,ptr, value.integrationId,"THERMOSTAT_" .. value.integrationId,DEVTYPE[value.devType],"D_HVAC_ZoneThermostat1.xml","","",false)
            g_occupancyFlag = true
        elseif value.devType == "AREA" then
            luup.chdev.append(device,ptr, value.integrationId,"AREA_" .. value.integrationId,DEVTYPE[value.devType],"D_MotionSensor1.xml","","",false)
            g_occupancyFlag = true
        else
            log("(Homebridge PLugin)::(appendDevices) : ERROR : Unknown device type!")  
        end
        if index > 49 then
            log("(Homebridge PLugin)::(appendDevices) : ERROR : High number of new devices to create, possible ERROR!") 
            break
        end
    end
    luup.chdev.sync(device,ptr)
end

local function setChildID(device)
    for key, value in pairs(luup.devices) do
        if value.device_num_parent == device then
            for k,v in pairs(g_childDevices) do
                if v.integrationId == value.id then
                    g_childDevices[k].id = key
                end
            end
        end
    end
end

function setTarget(device,value)
    local integrationId = ""
    local switchType = ""
    local cmd = ""
    for k,v in pairs(g_childDevices) do
        if v.id == device then
            integrationId = v.integrationId
            switchType = v.devType
        end
    end


    debug("(homebridge2openluup PLugin)::(debug)::(setTarget) : Sending command :'" .. integrationId .."' ..." .. value)
    if switchType == "SW_POWER" then 
        homebridgePutDevice(integrationId, "On", value)
        luup.variable_set(SID["SW_POWER"], "Status", value, device)
    end

    if switchType == "SW_GATE" then 
        homebridgePutDevice(integrationId, "On", value)
        luup.variable_set(SID["SW_GATE"], "Status", value, device)
    end   

    if switchType == "LOCK" then 
        homebridgePutDevice(integrationId, "LockTargetState", value)
        luup.variable_set(SID["LOCK"], "Status", value, device)
    end 

end

function setLoadLevelTarget(device,value)
    local integrationId = ""
    local cmd = ""
    for k,v in pairs(g_childDevices) do
        if v.id == device then
            integrationId = v.integrationId
        end
    end

    debug("(homebridge2openluup PLugin)::(debug)::(setLoadLevelTarget) : Sending command :'" .. integrationId .."' ..." .. value)
    homebridgePutDevice(integrationId, "Brightness", tonumber(value))
    luup.variable_set(SID["DIMMER"],"LoadLevelTarget", tonumber(value), device)
end

function SetCurrentSetpoint(device,value)
    local g_tempformat = luup.attr_get "TemperatureFormat"
    local integrationId = ""
    local cmd = ""
    for k,v in pairs(g_childDevices) do
        if v.id == device then
            integrationId = v.integrationId
        end

    end
    local thermostatType = luup.variable_get(SID["TH_USER_MODE"],"Type",device) or ""
    local thermostatManu = luup.variable_get(SID["TH_USER_MODE"],"Manufacturer",device) or ""
    local thermostatModel = luup.variable_get(SID["TH_USER_MODE"],"Model",device) or ""

    if g_tempformat == "F" then
        debug(' Setpoint Cool celsius_temp converted to Fahr' .. round_temp(temp_celsius(value)))
        if thermostatModel == "nikeSmart" then -- FOR ECOBEE3
            homebridgePutDevice(integrationId, "TargetTemperature", round_temp(temp_celsius(value)))
            luup.variable_set(SID["TH_TEMP_SET"], "CurrentSetpoint", round_temp(value), device)
        else
            homebridgePutDevice(integrationId, "CoolingThresholdTemperature", round_temp(temp_celsius(value)))
            luup.variable_set(SID["TH_TEMP_SET"], "CurrentSetpoint", round_temp(value), device)
        end            
        debug("(homebridge2openluup PLugin)::(debug)::(SetCurrentSetpoint) : Sending command :'" .. integrationId .."' ..." .. round_temp(temp_celsius(value)))
    else
        debug(' Setpoint Cool celsius_temp kept' .. value)
        if thermostatModel == "nikeSmart" then -- FOR ECOBEE3
            homebridgePutDevice(integrationId, "TargetTemperature", round_temp(value))
            luup.variable_set(SID["TH_TEMP_SET"], "CurrentSetpoint", round_temp(value), device)
        else
            homebridgePutDevice(integrationId, "CoolingThresholdTemperature", round_temp(value))
            luup.variable_set(SID["TH_TEMP_SET"], "CurrentSetpoint", round_temp(value), device)
        end            
            debug("(homebridge2openluup PLugin)::(debug)::(SetCurrentSetpoint) : Sending command :'" .. integrationId .."' ..." .. round_temp(value))

    end
end

function SetCurrentSetpoint_Cool(device,value)
    local g_tempformat = luup.attr_get "TemperatureFormat"
    local integrationId = ""
    local cmd = ""
    for k,v in pairs(g_childDevices) do
        if v.id == device then
            integrationId = v.integrationId
        end
    end

    local thermostatType = luup.variable_get(SID["TH_USER_MODE"],"Type",device) or ""
    local thermostatManu = luup.variable_get(SID["TH_USER_MODE"],"Manufacturer",device) or ""
    local thermostatModel = luup.variable_get(SID["TH_USER_MODE"],"Model",device) or ""

    if g_tempformat == "F" then
        debug(' Setpoint Cool celsius_temp converted to Fahr' .. round_temp(temp_celsius(value)))
        if thermostatModel == "nikeSmart" then -- FOR ECOBEE3
            homebridgePutDevice(integrationId, "TargetTemperature", round_temp(temp_celsius(value)))
            luup.variable_set(SID["TH_TEMP_SET_COOL"], "CurrentSetpoint", round_temp(value), device)
            debug("(homebridge2openluup TargetTemperature PLugin)::(debug)::(SetCurrentSetpoint_Cool) : Sending command :'" .. integrationId .."' ..." .. round_temp(temp_celsius(value)))
        else
            homebridgePutDevice(integrationId, "CoolingThresholdTemperature", round_temp(temp_celsius(value)))
            luup.variable_set(SID["TH_TEMP_SET_COOL"], "CurrentSetpoint", round_temp(value), device)
            debug("(homebridge2openluup CoolingThresholdTemperature PLugin)::(debug)::(SetCurrentSetpoint_Cool) : Sending command :'" .. integrationId .."' ..." .. round_temp(temp_celsius(value)))
        end
    else
        debug(' Setpoint Cool celsius_temp kept' .. value)
        if thermostatModel == "nikeSmart" then -- FOR ECOBEE3
            homebridgePutDevice(integrationId, "TargetTemperature", round_temp(value))
            luup.variable_set(SID["TH_TEMP_SET_COOL"], "CurrentSetpoint", round_temp(value), device)
        else
            homebridgePutDevice(integrationId, "CoolingThresholdTemperature", round_temp(value))
            luup.variable_set(SID["TH_TEMP_SET_COOL"], "CurrentSetpoint", round_temp(value), device)
        end
        debug("(homebridge2openluup CoolingThresholdTemperature PLugin)::(debug)::(SetCurrentSetpoint_Heat) : Sending command :'" .. integrationId .."' ..." .. round_temp(value))
    end
end

function SetCurrentSetpoint_Heat(device,value)
    local g_tempformat = luup.attr_get "TemperatureFormat"
    local integrationId = ""
    local cmd = ""
    for k,v in pairs(g_childDevices) do
        if v.id == device then
            integrationId = v.integrationId
        end
    end

    local thermostatType = luup.variable_get(SID["TH_USER_MODE"],"Type",device) or ""
    local thermostatManu = luup.variable_get(SID["TH_USER_MODE"],"Manufacturer",device) or ""
    local thermostatModel = luup.variable_get(SID["TH_USER_MODE"],"Model",device) or ""

    if g_tempformat == "F" then
        debug(' Setpoint Cool celsius_temp converted to Fahr' .. round_temp(temp_celsius(value)))
        if thermostatModel == "nikeSmart" then -- FOR ECOBEE3
            homebridgePutDevice(integrationId, "TargetTemperature", round_temp(temp_celsius(value)))
            luup.variable_set(SID["TH_TEMP_SET_HEAT"], "CurrentSetpoint", round_temp(value), device)
        else
            homebridgePutDevice(integrationId, "HeatingThresholdTemperature", round_temp(temp_celsius(value)))
            luup.variable_set(SID["TH_TEMP_SET_HEAT"], "CurrentSetpoint", round_temp(value), device)
        end
        debug("(homebridge2openluup HeatingThresholdTemperature PLugin)::(debug)::(SetCurrentSetpoint_Heat) : Sending command :'" .. integrationId .."' ..." .. round_temp(temp_celsius(value)))
    else
        debug(' Setpoint Cool celsius_temp kept' .. value)
        if thermostatModel == "nikeSmart" then -- FOR ECOBEE3
            homebridgePutDevice(integrationId, "TargetTemperature", round_temp(value))
            luup.variable_set(SID["TH_TEMP_SET_HEAT"], "CurrentSetpoint", round_temp(value), device)
        else
            homebridgePutDevice(integrationId, "HeatingThresholdTemperature", round_temp(value))
            luup.variable_set(SID["TH_TEMP_SET_HEAT"], "CurrentSetpoint", round_temp(value), device)
        end
        debug("(homebridge2openluup PLugin)::(debug)::(SetCurrentSetpoint_Heat) : Sending command :'" .. integrationId .."' ..." .. round_temp(value))

    end
end

function UserOpModeSetTarget(device,value)
    local integrationId = ""
    for k,v in pairs(g_childDevices) do
        if v.id == device then
            integrationId = v.integrationId
        end
    end

    local thermostatType = luup.variable_get(SID["TH_USER_MODE"],"Type",device) or ""

    if thermostatType == "Thermostat" then
        if value == "CoolOn" then
            homebridgePutDevice(integrationId, "TargetHeatingCoolingState", 2)
            debug("(homebridge2openluup PLugin)::(debug)::(SetModeTarget) 2: Sending command :'" .. integrationId .."' ..." .. value)
            elseif value == "HeatOn" then
            homebridgePutDevice(integrationId, "TargetHeatingCoolingState", 1)
            debug("(homebridge2openluup PLugin)::(debug)::(SetModeTarget) 1: Sending command :'" .. integrationId .."' ..." .. value)
            elseif value == "AutoChangeOver" then
            homebridgePutDevice(integrationId, "TargetHeatingCoolingState", 3)
            debug("(homebridge2openluup PLugin)::(debug)::(SetModeTarget) 0: Sending command :'" .. integrationId .."' ..." .. value)
            luup.variable_set(SID["TH_USER_MODE"], "ModeStatus", value, device)
        end
    elseif thermostatType == "HeaterCooler" then
        if value == "CoolOn" then
            homebridgePutDevice(integrationId, "TargetHeaterCoolerState", 2)
            debug("(homebridge2openluup PLugin)::(debug)::(SetModeTarget) 2: Sending command :'" .. integrationId .."' ..." .. value)
            elseif value == "HeatOn" then
            homebridgePutDevice(integrationId, "TargetHeaterCoolerState", 1)
            debug("(homebridge2openluup PLugin)::(debug)::(SetModeTarget) 1: Sending command :'" .. integrationId .."' ..." .. value)
            elseif value == "AutoChangeOver" then
            homebridgePutDevice(integrationId, "TargetHeaterCoolerState", 0)
            debug("(homebridge2openluup PLugin)::(debug)::(SetModeTarget) 0: Sending command :'" .. integrationId .."' ..." .. value)
            luup.variable_set(SID["TH_USER_MODE"], "ModeStatus", value, device)
        end
    end    
end        

function monitorHomebrideDevices()

    for k,v in pairs(g_childDevices) do
        debug('g_childDevices ID = '.. k ..' '..v.id)
        debug('g_childDevices IntegrationId = '.. k ..' '..v.integrationId)
        debug('g_childDevices devType = '.. k ..' '..v.devType)
        homebridgeGetDeviceValues(v.id,v.devType,v.integrationId)
    end
    luup.call_delay('monitorHomebrideDevices', 5, '')
end

function luaStartUp(lul_device)
    THIS_LUL_DEVICE = lul_device
    debug('luaStartUp running')

    m_Connected = false
    updateVariable('Connected', '0')

    updateVariable('PluginVersion', PLUGIN_VERSION)

    getInfo(THIS_LUL_DEVICE)
    --local ipa = luup.devices[THIS_LUL_DEVICE].ip
    --ipAddress = string.match(ipa, '^(%d%d?%d?%.%d%d?%d?%.%d%d?%d?%.%d%d?%d?)')

    --if ((ipAddress == nil) or (ipAddress == '')) then return false, 'Enter a valid IP address', PLUGIN_NAME end

    local homebridgeURL = "http://"..ipAddress..":"..ipPort.."/"
    updateVariable('homebridgeURL', homebridgeURL)
    getDevices(THIS_LUL_DEVICE)
    appendDevices(THIS_LUL_DEVICE)
    homebridgeLogin()
    luup.sleep(200)
    homebridgeGetDevices()
    setChildID(THIS_LUL_DEVICE)
    --homebridgeGetDeviceValues("c4e93bc2fafce70324785e3b50270e6850cf1b09b406e0e1bc05d77c212d5d04")
    luup.sleep(400)
    --homebridgePutDevice("c4e93bc2fafce70324785e3b50270e6850cf1b09b406e0e1bc05d77c212d5d04","TargetTemperature","18")
    monitorHomebrideDevices()



    -- required for UI7
    luup.set_failure(false)

    return true, 'All OK', PLUGIN_NAME
end