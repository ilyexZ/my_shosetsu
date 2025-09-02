-- {"id":19691969,"ver":"3.1.1","libVer":"1.0.0","author":"ilyexZ"}
local baseURL = "https://kolnovel.site"

local function shrinkURL(url)
    return url:gsub(baseURL, "")
end

local function expandURL(url)
    return baseURL .. url
end

-- Helper function to extract chapter numbers from text (more flexible)
local function extractChapterNumber(text)
    if not text then
        return nil
    end
    local number = text:match("(%d+)")
    return number and tonumber(number) or nil
end

-- Helper function to clean chapter title (remove novel name prefix)
local function cleanChapterTitle(chapterText, novelTitle)
    if not chapterText or not novelTitle then
        return chapterText or ""
    end

    -- Escape special pattern characters in novel title
    local escapedTitle = novelTitle:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")

    -- Try to remove novel name prefix
    local cleaned = chapterText:match("^" .. escapedTitle .. "%s*(.+)$")
    return cleaned and cleaned:gsub("^%s+", ""):gsub("%s+$", "") or chapterText
end

-- Helper function to detect locked chapters
local function isChapterLocked(text)
    if not text then
        return false
    end
    return text:find("🔒") ~= nil or text:find("locked") ~= nil or text:find("premium") ~= nil
end

-- Helper function to determine novel status from Arabic/English text
local function parseNovelStatus(statusText)
    if not statusText then
        return 3
    end -- Unknown

    local status = statusText:lower():gsub("الحالة:%s*", ""):gsub(":%s*", ""):gsub("%s+", " ")

    -- Completed
    if status:find("مكتملة") or status:find("completed") or status:find("complété") or status:find("completo") or
        status:find("completado") or status:find("tamamlandı") then
        return 1
        -- Ongoing
    elseif status:find("مستمرة") or status:find("ongoing") or status:find("en cours") or
        status:find("em andamento") or status:find("en progreso") or status:find("devam ediyor") then
        return 0
        -- Hiatus
    elseif status:find("متوقفة") or status:find("hiatus") or status:find("en pause") or status:find("hiato") or
        status:find("pausa") or status:find("pausado") or status:find("duraklatıldı") then
        return 2
    else
        return 3 -- Unknown
    end
end

-- Enhanced error handling for HTTP requests
local function safeGETDocument(url)
    local success, document = pcall(function()
        return GETDocument(url)
    end)

    if not success then
        print("Error fetching URL: " .. url .. " - " .. tostring(document))
        return nil
    end

    -- Check for captcha or redirection issues
    local title = document:select("title"):first()
    if title then
        local titleText = title:text()
        if titleText then
            titleText = titleText:lower()
            if titleText:find("bot verification") or titleText:find("you are being redirected") or
                titleText:find("un instant") or titleText:find("just a moment") or titleText:find("redirecting") or
                titleText:find("checking your browser") then
                error("Captcha detected or site blocked access. Please try opening in webview.")
            end
        end
    end

    return document
end

-- Helper function to extract text with fallbacks
local function extractText(element)
    if not element then
        return ""
    end
    local text = element:text()
    return text and text:gsub("^%s+", ""):gsub("%s+$", "") or ""
end

-- Helper function to extract attribute with fallbacks
local function extractAttr(element, attr)
    if not element then
        return nil
    end
    return element:attr(attr)
end

-- Helper function to find first non-empty element from multiple selectors
local function selectFirstFromSelectors(document, selectors)
    for _, selector in ipairs(selectors) do
        local element = document:selectFirst(selector)
        if element then
            local text = extractText(element)
            if text and text ~= "" then
                return element, text
            end
        end
    end
    return nil, ""
end

-- Helper function to collect all elements from multiple selectors
local function selectAllFromSelectors(document, selectors)
    local allElements = {}
    for _, selector in ipairs(selectors) do
        local elements = document:select(selector)
        for i = 1, elements:size() do
            table.insert(allElements, elements:get(i - 1))
        end
    end
    return allElements
end

-- Remove site watermark text, robustly and safely
local function sanitizeContent(s)
    if not s then
        return ""
    end
    -- 1) remove asterisks the site injects between letters/words
    s = s:gsub("%*", "")
    -- 2) remove the known Arabic line + kolnovel bits (allow flexible spaces)
    --    e.g. "إقرأ رواياتنا فقط على موقع ملوك الروايات kolnovel kolnovel . com"
    s = s:gsub(
        "إقرأ%s*رواياتنا%s*فقط%s*على%s*مو?قع%s*ملوك%s*الروايات.-[Kk][Oo][Ll][Nn]?[Oo]?[Vv][Ee][Ll].-[Cc][Oo][Mm]",
        "")
    -- 3) also strip any stray "kolnovel" tokens
    s = s:gsub("[Kk][Oo][Ll][Nn]?[Oo]?[Vv][Ee][Ll]%.?%s*[Cc]?[Oo]?[Mm]?", "")
    -- trim leftovers
    s = s:gsub("%s+\n", "\n"):gsub("\n%s+", "\n"):gsub("^%s+", ""):gsub("%s+$", "")
    return s
end

return {
    id = 19691969,
    name = "Kolnovel - ملوك الروايات",
    baseURL = baseURL,
    imageURL = "https://github.com/shosetsuorg/extensions/raw/dev/icons/Kolnovel.png",
    hasSearch = true,

    listings = {Listing("Novel List", true, function(data)
        local url = baseURL .. "/series/?page=" .. data[PAGE]
        local d = safeGETDocument(url)
        if not d then
            return {}
        end

        -- More robust novel extraction with multiple selector attempts
        local novels = {}
        local articleSelectors = {"article", "div.bsx", "div.listupd article", "div.post"}

        for _, selector in ipairs(articleSelectors) do
            local articles = d:select(selector)
            if articles:size() > 0 then
                for i = 1, articles:size() do
                    local article = articles:get(i - 1)

                    -- Try multiple link selectors
                    local linkElement = article:selectFirst("a[title]") or article:selectFirst("a[href*='knovel']") or
                                            article:selectFirst("a")

                    if linkElement then
                        local title = extractAttr(linkElement, "title") or extractText(linkElement)
                        local link = extractAttr(linkElement, "href")

                        if title and link and title ~= "" then
                            -- Try multiple image selectors
                            local imgElement =
                                article:selectFirst("img[data-src]") or article:selectFirst("img[src]") or
                                    article:selectFirst("img")

                            local imageURL = nil
                            if imgElement then
                                imageURL = extractAttr(imgElement, "data-src") or extractAttr(imgElement, "src")
                            end

                            table.insert(novels, Novel {
                                title = title,
                                imageURL = imageURL,
                                link = shrinkURL(link)
                            })
                        end
                    end
                end
                break -- If we found novels with this selector, don't try others
            end
        end

        return novels
    end), Listing("Latest", true, function(data)
        local url = baseURL .. "/page/" .. data[PAGE] .. "/"
        local d = safeGETDocument(url)
        if not d then
            return {}
        end

        return map(d:select("article, div.bsx, div.post"), function(v)
            local linkElement = v:selectFirst("a")
            local titleElement = v:selectFirst("h2, h3, .ntitle, .title")
            local imgElement = v:selectFirst("img")

            if linkElement and titleElement then
                return Novel {
                    title = extractText(titleElement),
                    imageURL = imgElement and (extractAttr(imgElement, "data-src") or extractAttr(imgElement, "src")) or
                        nil,
                    link = shrinkURL(extractAttr(linkElement, "href"))
                }
            end
            return nil
        end)
    end)},

    parseNovel = function(novelURL, loadChapters)
        local document = safeGETDocument(expandURL(novelURL))
        if not document then
            return nil
        end

        local novelInfo = NovelInfo()

        -- Title extraction with multiple fallbacks
        local titleSelectors = {"h1.entry-title", "h1", ".ts-post-image", ".novel-title", ".book-title"}
        local titleElement, titleText = selectFirstFromSelectors(document, titleSelectors)

        if titleText == "" and titleElement then
            titleText = extractAttr(titleElement, "title") or extractAttr(titleElement, "alt")
        end
        novelInfo:setTitle(titleText ~= "" and titleText or "Unknown Title")

        -- Cover image extraction (improved + absolute URL)
        local imgSelectors = {".ts-post-image img", ".ts-post-image", "div.bigcover img", "img[data-src]",
                              ".novel-cover img", ".book-cover img", "img[src]"}
        for _, selector in ipairs(imgSelectors) do
            local imgElement = document:selectFirst(selector)
            if imgElement then
                local imageURL = extractAttr(imgElement, "data-src") or extractAttr(imgElement, "src")
                if imageURL then
                    if not imageURL:match("^https?://") then
                        if imageURL:sub(1, 1) == "/" then
                            imageURL = baseURL .. imageURL
                        else
                            imageURL = baseURL .. "/" .. imageURL
                        end
                    end
                    novelInfo:setImageURL(imageURL)
                    break
                end
            end
        end

        -- Description extraction
        local descSelectors = {"div.entry-content", "div.description", ".novel-description", ".summary"}
        local _, descText = selectFirstFromSelectors(document, descSelectors)
        if descText ~= "" then
            novelInfo:setDescription(descText)
        end

        -- Status parsing with broader search
        local statusElements = selectAllFromSelectors(document,
            {"div.info-content span", ".spe span", ".serl span", ".sertostat", ".novel-info span", ".book-info span",
             "div.novel-details span"})

        for _, element in ipairs(statusElements) do
            local statusText = extractText(element)
            if statusText and
                (statusText:find("الحالة") or statusText:find("[Ss]tatus") or statusText:find("حالة")) then
                novelInfo:setStatus(NovelStatus(parseNovelStatus(statusText)))
                break
            end
        end

        -- Authors extraction
        local authors = {}
        local authorElements = selectAllFromSelectors(document, {"div.info-content span a", ".spe a", ".serl a",
                                                                 ".author a", ".novel-author a", ".book-author a"})

        for _, element in ipairs(authorElements) do
            local authorText = extractText(element)
            if authorText ~= "" then
                table.insert(authors, authorText)
            end
        end
        if #authors > 0 then
            novelInfo:setAuthors(authors)
        end

        -- Genres extraction
        local genres = {}
        local genreElements = selectAllFromSelectors(document, {"div.genxed a", ".sertogenre a", ".genre-info a",
                                                                ".genres a", ".novel-genres a", ".categories a"})

        for _, element in ipairs(genreElements) do
            local genreText = extractText(element)
            if genreText ~= "" then
                table.insert(genres, genreText)
            end
        end
        if #genres > 0 then
            novelInfo:setGenres(genres)
        end

        -- ... (keep the code the same until the chapters section in parseNovel function)

        if loadChapters then
            -- Multiple approaches to find chapters
            local chapterSelectors = {".eplister ul li", ".bixbox .epcheck ul li", "div.epcontent ul li",
                                      ".chapter-list li", ".chapters li", "ul.chapter-list li"}

            local chapters = {}
            local novelTitle = novelInfo:getTitle()

            for _, selector in ipairs(chapterSelectors) do
                local chapterElements = document:select(selector)
                if chapterElements:size() > 0 then
                    for i = 1, chapterElements:size() do
                        local chapterItem = chapterElements:get(i - 1)
                        local chapterLink = chapterItem:selectFirst("a")

                        if chapterLink then
                            local href = extractAttr(chapterLink, "href")
                            if href then
                                local chapter = NovelChapter()
                                chapter:setLink(shrinkURL(href))

                                -- Extract chapter title from multiple possible elements
                                local titleElement = chapterItem:selectFirst(".epl-title") or
                                                         chapterItem:selectFirst(".chapter-title") or
                                                         chapterItem:selectFirst(".chapternum") or chapterLink

                                local chapterTitle = extractText(titleElement)
                                local chapterNumber = extractChapterNumber(chapterTitle)

                                -- Clean the title
                                chapterTitle = cleanChapterTitle(chapterTitle, novelTitle)

                                -- Check if chapter is locked
                                if isChapterLocked(chapterTitle) and not chapterTitle:find("🔒") then
                                    chapterTitle = "🔒 " .. chapterTitle
                                end

                                chapter:setTitle(chapterTitle)
                                chapter:setOrder(chapterNumber or (#chapters + 1))

                                table.insert(chapters, chapter)
                            end
                        end
                    end
                    break -- If we found chapters with this selector, don't try others
                end
            end

            -- REMOVED the chapter reversing code - chapters will now stay in original order
            novelInfo:setChapters(AsList(chapters))
        end

-- ... (keep the rest of the code the same)

        return novelInfo
    end,

    getPassage = function(chapterURL)
        local document = safeGETDocument(expandURL(chapterURL))
        if not document then
            return "Error loading chapter content."
        end

        local contentSelectors = {"div.epcontent", "article div.entry-content", "div.chapter-content", ".content",
                                  ".chapter-text", ".text-content"}

        for _, selector in ipairs(contentSelectors) do
            local contentElement = document:selectFirst(selector)
            if contentElement then
                local unwantedSelectors = {".code-block", ".ads", "script", "style", ".advertisement", ".ad"}
                for _, unwantedSelector in ipairs(unwantedSelectors) do
                    local unwantedElements = contentElement:select(unwantedSelector)
                    for j = 1, unwantedElements:size() do
                        unwantedElements:get(j - 1):remove()
                    end
                end

                local paragraphs = contentElement:select("p")
                local content = {}
                if paragraphs:size() > 0 then
                    for j = 1, paragraphs:size() do
                        local pText = extractText(paragraphs:get(j - 1))
                        if pText ~= "" then
                            -- Apply sanitization to remove watermark
                            pText = sanitizeContent(pText)
                            table.insert(content, pText)
                        end
                    end
                else
                    local allText = extractText(contentElement)
                    if allText ~= "" then
                        -- Apply sanitization to remove watermark
                        allText = sanitizeContent(allText)
                        table.insert(content, allText)
                    end
                end

                if #content > 0 then
                    local passage = table.concat(content, "\n\n")
                    -- Remove the u{202B} character and use HTML for RTL formatting
                    return "<div style='text-align: right; direction: rtl;'>" .. passage .. "</div>"
                end
            end
        end

        return "Unable to extract chapter content."
    end,

    search = function(data)
        local url = baseURL .. "/page/" .. data[PAGE] .. "/?s=" .. data[QUERY]
        local d = safeGETDocument(url)
        if not d then
            return {}
        end

        return map(d:select("article, div.bsx"), function(v)
            local linkElement = v:selectFirst("a")
            local titleElement = v:selectFirst("h2, h3, .ntitle, span.ntitle")
            local imgElement = v:selectFirst("img")

            if linkElement and titleElement then
                return Novel {
                    title = extractText(titleElement),
                    imageURL = imgElement and (extractAttr(imgElement, "data-src") or extractAttr(imgElement, "src")) or
                        nil,
                    link = shrinkURL(extractAttr(linkElement, "href"))
                }
            end
            return nil
        end)
    end,

    shrinkURL = shrinkURL,
    expandURL = expandURL
}
