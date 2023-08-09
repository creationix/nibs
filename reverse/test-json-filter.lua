local json_filter = require './json-filter'

local tests = {
    '{"name":"Filter","age":100}', {name=true},'{"name":"Filter"}',
    '{"name":"Filter","age":100}', {age=true},'{"age":100}',
    '{"name":"Filter","age":100}', {name=true,age=true},'{"name":"Filter","age":100}',
    '{"name":"Filter","age":100}', {},'{}',
    '{"name":[1,2,3],"age":{"a":null}}', {name=true},'{"name":[1,2,3]}',
    '{"name":[1,2,3],"age":{"a":null}}', {age=true},'{"age":{"a":null}}',
    '{"name":[1,2,3],"age":{"a":null}}', {name=true,age=true},'{"name":[1,2,3],"age":{"a":null}}',
    '{"name":[1,2,3],"age":{"a":null}}', {},'{}',
    '{"a":1,"b":2,"c":3,"d":4}',{a=true,c=true},'{"a":1,"c":3}',
    '{"a":1,"b":2,"c":3,"d":4}',{b=true,d=true},'{"b":2,"d":4}',
    '{"a":1,"b":2,"c":3,"d":4}',{b=true,c=true},'{"b":2,"c":3}',
    '{"a":1,"b":2,"c":3,"d":4}',{a=true,d=true},'{"a":1,"d":4}',
    '{"a":1,"b":2,"c":3,"d":4}',{c=true,d=true},'{"c":3,"d":4}',
    '{"a":1,"b":2,"c":3,"d":4}',{a=true,b=true},'{"a":1,"b":2}',
    '{"a":[{}],"b":[[]],"c":[],"d":{}}',{},'{}',
    '{"a":[{}],"b":[[]],"c":[],"d":{}}',{a=true,c=true},'{"a":[{}],"c":[]}',
    '{"a":[{}],"b":[[]],"c":[],"d":{}}',{b=true,d=true},'{"b":[[]],"d":{}}',
}
for i = 1, #tests, 3 do
    local input_json = tests[i]
    ---@type table<string,boolean>
    local keep_fields = tests[i+1]
    local expected_output_json = tests[i+2]
    local actual_output_json = json_filter(input_json, keep_fields)
    print(input_json,keep_fields,actual_output_json,expected_output_json)
    assert(expected_output_json == actual_output_json, "JSON mismatch")
end

print("All tests passed")
