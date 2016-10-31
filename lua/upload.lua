local upload = require "resty.upload"
local cjson = require "cjson"
local get = ngx.req.get_uri_args()
local chunk_size = 4096
local file_upload_count = 0
local speed = 0
local post = {}
local index
local file
local upload_path = "/tmp/" -- 上传路径

-- 合并分片
local function mergeChunks(chunks, name)
    local file = io.open(upload_path .. name, "w+")
    -- 遍历小碎片
    for i = 0, chunks - 1 do
        local chunk_path = upload_path .. name .. "." .. i
        local chunk_file = io.open(chunk_path)
        while true do
            local bytes = chunk_file:read(4096)
            if not bytes then
                break
            end
            file:write(bytes) --依次写入主文件
        end
        chunk_file:close()
        os.remove(chunk_path)
    end
    file:close()
end

-- 限速计算
if get.speed then
    speed = math.ceil(get.speed * 1024 / chunk_size)
end

local form, err = upload:new(chunk_size)
if not form then
    ngx.say("no zuo no die.")
    ngx.exit(200)
end

form:set_timeout(1000) -- 一秒超时

while true do
    local typ, res, err = form:read()
    if not typ then
        ngx.say("failed to read: ", err)
        return
    end

    if typ == "header" then
        if res[1] == "Content-Disposition" then
            local filename = ngx.re.match(res[2], '(.+)filename="(.+)"(.*)')

            if filename then
                filename = filename[2]

                -- 分片上传
                if post["chunks"] then
                    filename = filename .. "." .. post["chunk"]
                end

                file = io.open(upload_path .. filename, "w+")
                if not file then
                    ngx.say("failed to open file ")
                    return
                end
            else
                local name = ngx.re.match(res[2], '(.+)name="(.+)"(.*)')
                if name[2] then
                    index = name[2]
                end    
            end
        end
    elseif typ == "body" then
        if file then
            -- 记录上传次数
            file_upload_count = file_upload_count + 1

            -- 专业限速
            if speed ~= 0 and file_upload_count % speed == 0 then
                ngx.sleep(1)
            end

            -- 写文件
            file:write(res)
        else
            -- 获取到全部body前记录post数据
            if index then
                if post[index] == nil then
                    post[index] = res
                else
                    post[index] = post[index] .. res
                end
            end
        end
    elseif typ == "part_end" then
        if file then
            -- 文件上传完毕
            file:close()
            file = nil

            if post["chunks"] and post["chunk"] then
                -- 合并分片
                if tonumber(post["chunks"]) - tonumber(post["chunk"]) == 1 then
                    mergeChunks(tonumber(post["chunks"]), post["name"])
                end
            end

            ngx.header["Content-Type"] = 'application/json'
            ngx.say(cjson.encode({code=1}))
        end
        if index then
            index = nil
        end
    elseif typ == "eof" then
        break
    else
        -- 干点嘛
    end

end