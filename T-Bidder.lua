--[[
	T-Bidder v1.18 RU Remaster for Turtle WoW
	Original author: Misha (Wht Mst)
	Based on: DKPAuctionBidder
	GitHub: https://github.com/whtmst/T-Bidder

	Аддон для участия в DKP аукционах в рейде.
	Отслеживает ставки, таймеры и результаты аукционов.
	Last update:	v1.18
	Tested for:		Turtle WoW
]]--

-- Идентификаторы аддона для коммуникации
local T_Bidder_Identifier = "TBidder"
local T_Bidder_SOTAprefix = "SOTAv1"

-- Цветовые коды для текста
local T_Bidder_CHAT_END = "|r"  -- Сброс цвета к стандартному
local T_Bidder_COLOUR_INTRO = "|c80F0F0F0"  -- Светло-серый цвет для интерфейса
local T_Bidder_COLOUR_CHAT = "|c8040A0F8"   -- Голубой цвет для сообщений в чате

-- Состояния аукциона:
-- 0=нет аукциона, 1=аукцион идет, 2=есть ставки, 3=приостановлен, 4=ожидание победителя, 5=победитель объявлен
local T_Bidder_AuctionState = 0
local T_Bidder_AuctionStatePrePause = 0  -- Состояние до паузы (для восстановления)

-- Данные игрока и аукциона
local T_Bidder_PlayerDKP = 0  -- Текущие ДКП игрока
local T_Bidder_SOTA_Master = ""  -- Имя мастера SotA аддона
local T_Bidder_SubmitBidTimer = 5  -- Таймер между ставками (защита от спама)
local T_Bidder_SubmitBidFlag = 1  -- Флаг разрешения ставки (1=можно ставить)

-- Таймеры аукциона
local T_Bidder_AuctionTime = 0  -- Общее время аукциона
local T_Bidder_AuctionTimeLeft = 0  -- Оставшееся время аукциона
local T_Bidder_AuctionTimerUpdateRate = 0.05  -- Частота обновления таймера

-- Интерфейсные переменные
local T_Bidder_StatusbarStandardwidth = 0  -- Стандартная ширина статус-бара
local T_Bidder_IsShown = 0  -- Флаг отображения интерфейса (0=скрыт, 1=показан)
local T_Bidder_MinimumStartingBid = 30  -- Минимальная стартовая ставка

-- Переменные для отслеживания победителя
local T_Bidder_AuctionWinner = ""  -- Имя победителя аукциона
local T_Bidder_WinnerBidAmount = 0  -- Сумма ставки победителя
local T_Bidder_AuctionItem = ""  -- Название предмета аукциона
local T_Bidder_AuctionWinnerClass = ""  -- Класс победителя

-- Данные о ставках
local T_Bidder_Currentbid = {}  -- Текущая максимальная ставка
local T_Bidder_LastHighestBid = {}  -- Последняя максимальная ставка (для восстановления после паузы)

local T_Bidder_AuctionMaster = ""  -- Имя ведущего аукцион

-- Цвета классов для окрашивания имен игроков в соответствии с WoW
local T_Bidder_CLASS_COLORS = {
    { "Druid", { 255,125, 10 } },    -- оранжевый
    { "Hunter", { 171,212,115 } },   -- зеленый
    { "Mage", { 105,204,240 } },     -- голубой
    { "Paladin", { 245,140,186 } },  -- розовый
    { "Priest", { 255,255,255 } },   -- белый
    { "Rogue", { 255,245,105 } },    -- желтый
    { "Shaman", { 0,112,222 } },     -- синий
    { "Warlock", { 148,130,201 } },  -- фиолетовый
    { "Warrior", { 199,156,110 } }   -- коричневый
}

-- Вспомогательная функция для обрезки пробелов в начале и конце строки
function string.trim(str)
    if not str then return "" end
    return string.gsub(str, "^%s*(.-)%s*$", "%1")
end

-- Основная функция обработки событий аддона
function T_Bidder_OnEvent(event, arg1, arg2, arg3, arg4, arg5)
    if (event == "CHAT_MSG_ADDON") then
        T_Bidder_OnChatMsgAddon(event, arg1, arg2, arg3, arg4, arg5)
    end
    if (event == "GUILD_ROSTER_UPDATE") then
        T_Bidder_GetPlayerDKP()
    end
    if (event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" or event == "CHAT_MSG_RAID_WARNING") then
        T_Bidder_OnChatMsgRaid(event, arg1, arg2, arg3, arg4, arg5)
    end
end

-- Функция загрузки аддона при входе в игру
function T_Bidder_OnLoad()
    this:RegisterEvent("ADDON_LOADED")
    this:RegisterEvent("GUILD_ROSTER_UPDATE")
    this:RegisterEvent("CHAT_MSG_ADDON")
    this:RegisterEvent("CHAT_MSG_RAID")
    this:RegisterEvent("CHAT_MSG_RAID_LEADER")
    this:RegisterEvent("CHAT_MSG_RAID_WARNING")
    getglobal("T_Bidder_MinimapButtonFrame"):Show()
	T_Bidder_PlayerDKP = 0

    -- Загружаем данные гильдии если игрок в гильдии
    if IsInGuild() then
        GuildRoster()
    end

    T_Bidder_GetPlayerDKP()
    T_Bidder_StatusbarStandardwidth = getglobal("T_BidderUIFrameAuctionStatusbar"):GetWidth()
end

-- Функция отправки ставки ведущему аукциона или в рейд
function T_Bidder_SendBid(bidText)
    if T_Bidder_AuctionMaster and T_Bidder_AuctionMaster ~= "" then
        -- Отправляем ставку личным сообщением мастеру аукциона
        SendChatMessage(bidText, "WHISPER", nil, T_Bidder_AuctionMaster)
        DEFAULT_CHAT_FRAME:AddMessage(T_Bidder_COLOUR_CHAT .. "Ставка отправлена " .. T_Bidder_AuctionMaster .. ": " .. bidText .. T_Bidder_CHAT_END)
    else
        -- Отправляем ставку через аддон-сообщение в рейд
        SendAddonMessage(T_Bidder_Identifier, bidText, "RAID")
        DEFAULT_CHAT_FRAME:AddMessage(T_Bidder_COLOUR_CHAT .. "Ставка отправлена в рейд: " .. bidText .. T_Bidder_CHAT_END)
    end
end

-- Обработчик кнопки минимальной ставки
function T_Bidder_BidMinOnClick()
    if T_Bidder_SubmitBidFlag == 1 then
        T_Bidder_SendBid("bid min")
        T_Bidder_SubmitBidFlag = 0  -- Блокируем повторные ставки
    end
end

-- Обработчик кнопки максимальной ставки (все ДКП)
function T_Bidder_BidMaxOnClick()

	local dkp = T_Bidder_PlayerDKP or 0
    local confirmText = "Вы уверены, что \n хотите поставить \n ВСЕ (" .. dkp ..") \n ваши очки ДКП?"

    local textElement = getglobal("T_BidderMaxBidConfirmTextButtonText")
    if textElement then
        textElement:SetText(confirmText)
        T_BidderMaxBidConfirmationFrame:Show()  -- Показываем окно подтверждения
    else
        DEFAULT_CHAT_FRAME:AddMessage("Ошибка: не найден элемент подтверждения")
    end
end

-- Обработчик произвольной ставки (ввод числа)
function T_Bidder_BidXOnEnter(dkp)
    if T_Bidder_SubmitBidFlag == 1 then
        T_Bidder_SendBid("bid " .. dkp)
        T_Bidder_SubmitBidFlag = 0  -- Блокируем повторные ставки
    end
end

-- Подтверждение максимальной ставки (нажатие ДА в окне подтверждения)
function T_Bidder_MaxBidConfirmOnClick()

	local dkp = T_Bidder_PlayerDKP or 0

    if T_Bidder_SubmitBidFlag == 1 then
        getglobal("T_BidderMaxBidConfirmTextButtonText"):SetText("Вы уверены, что хотите \n поставить ВСЕ ваши очки ДКП (" .. dkp ..")?")
        T_Bidder_SendBid("bid max")
        T_BidderMaxBidConfirmationFrame:Hide()  -- Скрываем окно подтверждения
        T_Bidder_SubmitBidFlag = 0  -- Блокируем повторные ставки
    end
end

-- Отмена максимальной ставки (нажатие НЕТ в окне подтверждения)
function T_Bidder_MaxBidDeclineOnClick()
    T_BidderMaxBidConfirmationFrame:Hide()  -- Скрываем окно подтверждения
end

-- Таймеры для обновления интерфейса
local T_Bidder_BidTimer = 0  -- Таймер между ставками
local T_Bidder_RefreshTimer = 0  -- Таймер обновления статус-бара

-- Функция обновления кадров (вызывается постоянно для обновления таймеров и статус-бара)
function T_Bidder_BidFrameOnUpdate(elapsed)
    T_Bidder_BidTimer = T_Bidder_BidTimer + elapsed
    T_Bidder_RefreshTimer = T_Bidder_RefreshTimer + elapsed

    -- Таймер между ставками (чтобы избежать спама)
    if T_Bidder_BidTimer > T_Bidder_SubmitBidTimer then
        T_Bidder_BidTimer = 0
        T_Bidder_SubmitBidFlag = 1  -- Разрешаем следующую ставку
    end

    -- Обновление статус-бара аукциона (только когда аукцион активен)
    if T_Bidder_AuctionState == 1 or T_Bidder_AuctionState == 2 then
        if T_Bidder_RefreshTimer > T_Bidder_AuctionTimerUpdateRate then
            if T_Bidder_AuctionTimeLeft > T_Bidder_AuctionTime then T_Bidder_AuctionTime = T_Bidder_AuctionTimeLeft end
            T_Bidder_AuctionTimeLeft = T_Bidder_AuctionTimeLeft - T_Bidder_RefreshTimer
            T_Bidder_RefreshTimer = 0
            local fraction = T_Bidder_AuctionTimeLeft / T_Bidder_AuctionTime
            if fraction >= 1 then fraction = 1 end
            local newwidth = math.floor(T_Bidder_StatusbarStandardwidth * fraction)
            if newwidth <= 0 then newwidth = 1 end
            getglobal("T_BidderUIFrameAuctionStatusbar"):SetWidth(newwidth)  -- Обновляем ширину статус-бара
        end
    end
end

-- Обработчик клика по кнопке миникарты (показать/скрыть интерфейс)
function T_Bidder_MinimapButtonOnClick()
    if T_Bidder_IsShown == 0 then
        T_BidderUIFrame:Show()
        -- Обновляем текст в зависимости от состояния аукциона
        if T_Bidder_AuctionState == 0 then
            getglobal("T_BidderHighestBidTextButtonText"):SetText("Нет аукциона")
            getglobal("T_BidderHighestBidTextButtonPlayer"):SetText("")
        elseif T_Bidder_AuctionState == 1 then
            getglobal("T_BidderHighestBidTextButtonText"):SetText("Аукцион идет - нет ставок")
            getglobal("T_BidderHighestBidTextButtonPlayer"):SetText("")
        elseif T_Bidder_AuctionState == 2 then
            local color = T_Bidder_GetClassColorCodes(T_Bidder_Currentbid[5] or "Warrior")
            local coloredText = "Макс. ставка: " .. T_Bidder_Currentbid[3] .. " (|cFF" ..
                               string.format("%02x%02x%02x", color[1], color[2], color[3]) ..
                               T_Bidder_Currentbid[4] .. "|r)"
            getglobal("T_BidderHighestBidTextButtonText"):SetText(coloredText)
            getglobal("T_BidderHighestBidTextButtonPlayer"):SetText("")
        elseif T_Bidder_AuctionState == 3 then
            getglobal("T_BidderHighestBidTextButtonText"):SetText("Аукцион приостановлен")
            getglobal("T_BidderHighestBidTextButtonPlayer"):SetText("")
        elseif T_Bidder_AuctionState == 4 then
            getglobal("T_BidderHighestBidTextButtonText"):SetText("Аукцион завершен (Ожидаем победителя)")
            getglobal("T_BidderHighestBidTextButtonPlayer"):SetText("")
        elseif T_Bidder_AuctionState == 5 then
            local color = T_Bidder_GetClassColorCodes(T_Bidder_AuctionWinnerClass or "Warrior")
            local coloredText = "Аукцион завершен (Победил - |cFF" ..
                               string.format("%02x%02x%02x", color[1], color[2], color[3]) ..
                               T_Bidder_AuctionWinner .. "|r)"
            getglobal("T_BidderHighestBidTextButtonText"):SetText(coloredText)
            getglobal("T_BidderHighestBidTextButtonPlayer"):SetText("")
        end
        T_Bidder_GetPlayerDKP()  -- Обновляем ДКП игрока
        T_Bidder_IsShown = 1  -- Помечаем интерфейс как показанный
    else
        T_Bidder_CloseUI()  -- Скрываем интерфейс
    end
end

-- Закрытие интерфейса аддона
function T_Bidder_CloseUI()
    T_BidderMaxBidConfirmationFrame:Hide()  -- Скрываем окно подтверждения если открыто
    T_BidderUIFrame:Hide()  -- Скрываем основной интерфейс
    T_Bidder_IsShown = 0  -- Помечаем интерфейс как скрытый
end

-- Функция для парсинга сообщения о победителе аукциона
function T_Bidder_ParseWinnerMessage(msg)
    local playerName, bidAmount, itemName

    -- Парсим сообщение формата: "[Small Glowing Shard] sold to Misha for 10 DKP."
    local itemStart, itemEnd = string.find(msg, "%[(.-)%]")
    if itemStart then
        itemName = string.sub(msg, itemStart + 1, itemEnd - 1)
    end

    local soldPos = string.find(msg, "sold to ")
    if soldPos then
        local forPos = string.find(msg, " for ", soldPos)
        if soldPos and forPos then
            playerName = string.sub(msg, soldPos + 8, forPos - 1)
            playerName = string.trim(playerName)

            -- Ищем сумму ставки
            local dkpPos = string.find(msg, " DKP", forPos)
            if forPos and dkpPos then
                bidAmount = string.sub(msg, forPos + 5, dkpPos - 1)
            end
        end
    end

    return playerName, bidAmount, itemName
end

-- Функция для получения класса победителя по имени
function T_Bidder_GetWinnerClass(playerName)
    local memberCount = GetNumGuildMembers()
    for n=1, memberCount, 1 do
        local name, rank, _, _, class = GetGuildRosterInfo(n)
        if name and string.lower(name) == string.lower(playerName) then
            return class
        end
    end
    return "Warrior" -- класс по умолчанию если не нашли в гильдии
end

-- Обработчик сообщений в рейдовом чате
function T_Bidder_OnChatMsgRaid(event, msg, sender, language, channel)
    -- Очистка сообщения от суффикса пьяного персонажа
    if msg then
        msg = string.gsub(msg, " %%.%%.%%.hic!$", "")
        msg = string.gsub(msg, " ish ", " is ")
    end

    -- Начало аукциона (мастер лута объявляет начало)
    if string.find(msg, "Auction open for") then
        T_Bidder_AuctionMaster = sender
        getglobal("T_BidderHighestBidTextButtonText"):SetText("Аукцион идет - ставок нет")
        getglobal("T_BidderHighestBidTextButtonPlayer"):SetText("")
        T_Bidder_GetPlayerDKP()

        T_BidderUIFrame:Show()
        T_BidderUIFrameAuctionStatusbar:Show()
        T_BidderUIFrameTimerFrame:Show()

        T_Bidder_AuctionTime = 30
        T_Bidder_AuctionTimeLeft = 30
        getglobal("T_BidderUIFrameAuctionStatusbar"):SetWidth(T_Bidder_StatusbarStandardwidth)

        T_Bidder_AuctionState = 1  -- Аукцион активен, ставок нет
        DEFAULT_CHAT_FRAME:AddMessage(T_Bidder_COLOUR_CHAT .. "Аукцион начат " .. sender .. T_Bidder_CHAT_END)
    end

    -- Отмена аукциона
    if string.find(msg, "Auction was Cancelled") then
        getglobal("T_BidderHighestBidTextButtonText"):SetText("Нет аукциона")
        getglobal("T_BidderHighestBidTextButtonPlayer"):SetText("")
        getglobal("T_BidderUIFrameAuctionStatusbar"):Hide()
        getglobal("T_BidderUIFrameTimerFrame"):Hide()
        getglobal("T_BidderBidMaxButton"):Enable()
        getglobal("T_BidderBidXButton"):Enable()
        T_Bidder_AuctionState = 0  -- Нет аукциона
        DEFAULT_CHAT_FRAME:AddMessage(T_Bidder_COLOUR_CHAT .. "Аукцион отменен" .. T_Bidder_CHAT_END)
    end

    -- Завершение аукциона (первый этап - ожидаем победителя)
    if string.find(msg, "Auction for") and string.find(msg, "is over") then
        getglobal("T_BidderHighestBidTextButtonText"):SetText("Аукцион завершен (Ожидаем победителя)")
        getglobal("T_BidderHighestBidTextButtonPlayer"):SetText("")
        getglobal("T_BidderUIFrameAuctionStatusbar"):Hide()
        getglobal("T_BidderUIFrameTimerFrame"):Hide()
        getglobal("T_BidderBidMaxButton"):Enable()
        getglobal("T_BidderBidXButton"):Enable()
        T_Bidder_AuctionState = 4 -- Новое состояние: ожидание победителя
        DEFAULT_CHAT_FRAME:AddMessage(T_Bidder_COLOUR_CHAT .. "Аукцион завершен (Ожидаем победителя)" .. T_Bidder_CHAT_END)
    end

    -- Продажа предмета (победитель аукциона) - второй этап
    if string.find(msg, "sold to") and string.find(msg, "for") and string.find(msg, "DKP") then
        local playerName, bidAmount, itemName = T_Bidder_ParseWinnerMessage(msg)

        if playerName and bidAmount then
            -- Сохраняем информацию о победителе
            T_Bidder_AuctionWinner = playerName
            T_Bidder_WinnerBidAmount = bidAmount
            T_Bidder_AuctionItem = itemName or "Предмет"
            T_Bidder_AuctionWinnerClass = T_Bidder_GetWinnerClass(playerName)

            -- Обновляем интерфейс с информацией о победителе
            local color = T_Bidder_GetClassColorCodes(T_Bidder_AuctionWinnerClass)
            local coloredText = "Аукцион завершен (Победил - |cFF" ..
                               string.format("%02x%02x%02x", color[1], color[2], color[3]) ..
                               playerName .. "|r)"

            getglobal("T_BidderHighestBidTextButtonText"):SetText(coloredText)
            getglobal("T_BidderHighestBidTextButtonPlayer"):SetText("")

            T_Bidder_AuctionState = 5 -- Финальное состояние: победитель объявлен

            DEFAULT_CHAT_FRAME:AddMessage(T_Bidder_COLOUR_CHAT .. "Победитель: " .. playerName .. " - " .. bidAmount .. " ДКП" .. T_Bidder_CHAT_END)
        end
    end

    -- Пауза аукциона
    if string.find(msg, "Auction has been Paused") then
        getglobal("T_BidderHighestBidTextButtonText"):SetText("Аукцион приостановлен")
        getglobal("T_BidderHighestBidTextButtonPlayer"):SetText("")
        T_Bidder_AuctionStatePrePause = T_Bidder_AuctionState  -- Сохраняем состояние до паузы
        T_Bidder_AuctionState = 3  -- Устанавливаем состояние паузы
        DEFAULT_CHAT_FRAME:AddMessage(T_Bidder_COLOUR_CHAT .. "Аукцион приостановлен" .. T_Bidder_CHAT_END)
    end

    -- Возобновление аукциона после паузы
    if string.find(msg, "Auction has been Resumed") then
        if T_Bidder_AuctionStatePrePause == 2 then
            -- Проверяем что данные о последней ставке существуют
            if T_Bidder_LastHighestBid and T_Bidder_LastHighestBid[3] and T_Bidder_LastHighestBid[4] then
                local color = {1, 1, 1} -- белый по умолчанию
                if T_Bidder_LastHighestBid[5] then
                    color = T_Bidder_GetClassColorCodes(T_Bidder_LastHighestBid[5])
                end
                local coloredText = "Макс. ставка: " .. T_Bidder_LastHighestBid[3] .. " (|cFF" ..
                                   string.format("%02x%02x%02x", color[1], color[2], color[3]) ..
                                   T_Bidder_LastHighestBid[4] .. "|r)"
                getglobal("T_BidderHighestBidTextButtonText"):SetText(coloredText)
                getglobal("T_BidderHighestBidTextButtonPlayer"):SetText("")
                T_Bidder_AuctionState = 2  -- Восстанавливаем состояние "есть ставки"
            else
                getglobal("T_BidderHighestBidTextButtonText"):SetText("Аукцион идет - нет ставок")
                getglobal("T_BidderHighestBidTextButtonPlayer"):SetText("")
                T_Bidder_AuctionState = 1  -- Восстанавливаем состояние "нет ставок"
            end
        elseif T_Bidder_AuctionStatePrePause == 1 then
            getglobal("T_BidderHighestBidTextButtonText"):SetText("Аукцион идет - нет ставок")
            getglobal("T_BidderHighestBidTextButtonPlayer"):SetText("")
            T_Bidder_AuctionState = 1  -- Восстанавливаем состояние "нет ставок"
        end
        DEFAULT_CHAT_FRAME:AddMessage(T_Bidder_COLOUR_CHAT .. "Аукцион возобновлен" .. T_Bidder_CHAT_END)

        -- Всегда показываем текущую минимальную ставку при возобновлении
        if T_Bidder_MinimumStartingBid and T_Bidder_MinimumStartingBid > 0 then
            DEFAULT_CHAT_FRAME:AddMessage(T_Bidder_COLOUR_CHAT .. "Минимальная ставка: " .. T_Bidder_MinimumStartingBid .. " ДКП" .. T_Bidder_CHAT_END)
        end
    end

    -- Объявление минимальной ставки
    if string.find(msg, "Minimum bid:") then
        local minBid
        local bidStart = string.find(msg, "Minimum bid: ")
        if bidStart then
            local numStart = string.find(msg, "%d", bidStart)
            local numEnd = string.find(msg, " DKP", numStart)
            if numStart and numEnd then
                minBid = string.sub(msg, numStart, numEnd - 1)
            end
        end

        if minBid then
            T_Bidder_MinimumStartingBid = tonumber(minBid)
            DEFAULT_CHAT_FRAME:AddMessage(T_Bidder_COLOUR_CHAT .. "Минимальная ставка: " .. minBid .. " ДКП" .. T_Bidder_CHAT_END)
        end
    end

	-- Обработка сообщений о ставках от SotA аддона
    local isBiddingMessage = string.find(msg, "is bidding") and string.find(msg, "DKP for")
    local isAllInMessage = string.find(msg, "went all in") and string.find(msg, "DKP") and string.find(msg, "for")

    if isBiddingMessage or isAllInMessage then
        local playerName, bidAmount

        -- Парсим имя после "] " и до " ("
        local startPos = string.find(msg, "%]%s*")
        if startPos then
            local afterBracket = string.sub(msg, startPos + 1)
            local nameEndPos = string.find(afterBracket, "%s*%(")
            if nameEndPos then
                playerName = string.sub(afterBracket, 1, nameEndPos - 1)
                playerName = string.trim(playerName)

                -- Ищем сумму ставки
                local numStart, numEnd
                if isBiddingMessage then
                    -- Формат: "is bidding 10 DKP for"
                    local bidStart = string.find(msg, "is bidding ")
                    if bidStart then
                        numStart = string.find(msg, "%d", bidStart)
                        numEnd = string.find(msg, " DKP", numStart)
                    end
                elseif isAllInMessage then
                    -- Формат: "went all in (3058 DKP) for"
                    local allInStart = string.find(msg, "went all in %(")
                    if allInStart then
                        numStart = string.find(msg, "%d", allInStart)
                        numEnd = string.find(msg, " DKP%)", numStart)
                    end
                end

                if numStart and numEnd then
                    bidAmount = string.sub(msg, numStart, numEnd - 1)
                end
            end
        end

        if playerName and bidAmount then
            -- Получаем цвет класса игрока из данных гильдии
            local classColor = {1, 1, 1}

            local memberCount = GetNumGuildMembers()
            for n=1, memberCount, 1 do
                local name, rank, _, _, class = GetGuildRosterInfo(n)
                if name and string.lower(name) == string.lower(playerName) then
                    classColor = T_Bidder_GetClassColorCodes(class)
                    break
                end
            end

            -- Формируем текст с маркером ALL-IN если это максимальная ставка
            local prefix = "Макс. ставка: "
            if isAllInMessage then
                prefix = "ALL-IN: "
            end

            local coloredText = prefix .. bidAmount .. " (|cFF" ..
                               string.format("%02x%02x%02x", classColor[1], classColor[2], classColor[3]) ..
                               playerName .. "|r)"

            getglobal("T_BidderHighestBidTextButtonText"):SetText(coloredText)
            getglobal("T_BidderHighestBidTextButtonPlayer"):SetText("")

            T_Bidder_AuctionState = 2

            local chatPrefix = isAllInMessage and "ALL-IN: " or "Ставка: "
            DEFAULT_CHAT_FRAME:AddMessage(T_Bidder_COLOUR_CHAT .. chatPrefix .. playerName .. " - " .. bidAmount .. " ДКП" .. T_Bidder_CHAT_END)
        end
    end
end

-- Обработчик аддон-сообщений (коммуникация между аддонами)
function T_Bidder_OnChatMsgAddon(event, prefix, msg, channel, sender)
    -- Дебаг информация (логируем все аддон-сообщения для отладки) - ЗАКОММЕНТИРОВАНО
    -- if prefix == T_Bidder_SOTAprefix or prefix == "SOTA_reply_TBidder" or prefix == "SOTA_TIMER_SYNC" then
    --     DEFAULT_CHAT_FRAME:AddMessage("DEBUG ADDON: prefix=[" .. prefix .. "] msg=[" .. msg .. "] sender=[" .. sender .. "]")
    -- end

    -- Ответы от SotA аддона
    if prefix == "SOTA_reply_TBidder" then
        if string.find(msg, UnitName("player")) == 1 then
            local message = string.sub(msg, string.len(UnitName("player"))+1)
            DEFAULT_CHAT_FRAME:AddMessage(T_Bidder_COLOUR_CHAT .. message .. T_Bidder_CHAT_END)
        end
    end

    -- Основные сообщения SotA аддона
    if prefix == T_Bidder_SOTAprefix then
        local msg_HB = string.sub(msg, 1, string.len("HIGEST_BID")+1)
        T_Bidder_Currentbid = T_Bidder_SplitString(msg)

        -- Начало аукциона через аддон SotA
        if string.find(msg, "SOTA_AUCTION_START") == 1 then
            getglobal("T_BidderHighestBidTextButtonText"):SetText("Аукцион идет - нет ставок")
            getglobal("T_BidderHighestBidTextButtonPlayer"):SetText("")
            T_Bidder_GetPlayerDKP()

            T_Bidder_AuctionTime = tonumber(T_Bidder_Currentbid[4])
            T_Bidder_AuctionTimeLeft = tonumber(T_Bidder_Currentbid[4])
            getglobal("T_BidderUIFrameAuctionStatusbar"):SetWidth(T_Bidder_StatusbarStandardwidth)

            T_Bidder_MinimumStartingBid = tonumber(T_Bidder_Currentbid[6])

            T_BidderUIFrame:Show()
            T_BidderUIFrameAuctionStatusbar:Show()
            T_BidderUIFrameTimerFrame:Show()

            T_Bidder_AuctionState = 1  -- Аукцион активен

        -- Получение информации о максимальной ставке от SotA
        elseif msg_HB == "HIGHEST_BID" then
            local color = T_Bidder_GetClassColorCodes(T_Bidder_Currentbid[5] or "Warrior")
            local coloredText = "Макс. ставка: " .. T_Bidder_Currentbid[3] .. " (|cFF" ..
                               string.format("%02x%02x%02x", color[1], color[2], color[3]) ..
                               T_Bidder_Currentbid[4] .. "|r)"
            getglobal("T_BidderHighestBidTextButtonText"):SetText(coloredText)
            getglobal("T_BidderHighestBidTextButtonPlayer"):SetText("")
            T_Bidder_LastHighestBid = T_Bidder_Currentbid  -- Сохраняем для восстановления после паузы
            T_Bidder_AuctionState = 2  -- Есть ставки

        -- Завершение или отмена аукциона через SotA
        elseif msg == "SOTA_AUCTION_FINISH" or msg == "SOTA_AUCTION_CANCEL" then
            if msg == "SOTA_AUCTION_FINISH" then
                getglobal("T_BidderHighestBidTextButtonText"):SetText("Аукцион завершен (Ожидаем победителя)")
                T_Bidder_AuctionState = 4 -- Ожидание победителя
            else
                getglobal("T_BidderHighestBidTextButtonText"):SetText("Нет аукциона")
                T_Bidder_AuctionState = 0  -- Аукцион отменен
            end
            getglobal("T_BidderHighestBidTextButtonPlayer"):SetText("")
            getglobal("T_BidderUIFrameAuctionStatusbar"):Hide()
            getglobal("T_BidderUIFrameTimerFrame"):Hide()
            getglobal("T_BidderBidMaxButton"):Enable()
            getglobal("T_BidderBidXButton"):Enable()

        -- Пауза аукциона через SotA
        elseif msg == "SOTA_AUCTION_PAUSE" then
            getglobal("T_BidderHighestBidTextButtonText"):SetText("Аукцион приостановлен")
            getglobal("T_BidderHighestBidTextButtonPlayer"):SetText("")
            T_Bidder_AuctionStatePrePause = T_Bidder_AuctionState  -- Сохраняем состояние до паузы
            T_Bidder_AuctionState = 3  -- Устанавливаем состояние паузы

        -- Возобновление аукциона через SotA
        elseif string.find(msg, "SOTA_AUCTION_RESUME") == 1 then
            if T_Bidder_AuctionStatePrePause == 2 then
                local color = T_Bidder_GetClassColorCodes(T_Bidder_LastHighestBid[5] or "Warrior")
                local coloredText = "Макс. ставка: " .. T_Bidder_LastHighestBid[3] .. " (|cFF" ..
                                   string.format("%02x%02x%02x", color[1], color[2], color[3]) ..
                                   T_Bidder_LastHighestBid[4] .. "|r)"
                getglobal("T_BidderHighestBidTextButtonText"):SetText(coloredText)
                getglobal("T_BidderHighestBidTextButtonPlayer"):SetText("")
                T_Bidder_AuctionTimeLeft = tonumber(T_Bidder_Currentbid[4])
                T_Bidder_AuctionState = 2  -- Восстанавливаем состояние "есть ставки"

            elseif T_Bidder_AuctionStatePrePause == 1 then
                getglobal("T_BidderHighestBidTextButtonText"):SetText("Аукцион идет - нет ставок")
                getglobal("T_BidderHighestBidTextButtonPlayer"):SetText("")
                T_Bidder_AuctionTimeLeft = tonumber(T_Bidder_Currentbid[4])
                T_Bidder_AuctionState = 1  -- Восстанавливаем состояние "нет ставок"
            end
        end

        -- Установка мастера SotA (ведущего аукциона)
        if msg == "SOTAMASTER" then
            T_Bidder_SOTA_Master = sender
        end
    end

    -- Синхронизация таймера между клиентами
    if prefix == "SOTA_TIMER_SYNC" then
        T_Bidder_AuctionTimeLeft = tonumber(msg)
    end
end

-- Функция получения ДКП игрока из заметок гильдии
function T_Bidder_GetPlayerDKP()
    local memberCount = GetNumGuildMembers()
    local note
    for n=1, memberCount, 1 do
        local name, rank, _, _, class, zone, publicnote, officernote, online = GetGuildRosterInfo(n)

        if name == UnitName("player") then
            if not zone then
                zone = ""
            end

            note = officernote -- Используем офицерскую заметку (обычно там хранятся ДКП)

            if not note or note == "" then
                note = "<0>"  -- Значение по умолчанию если заметка пустая
            end

            if not online then
                online = 0
            end

            -- Парсим ДКП из формата "<число>"
            local _, _, dkp = string.find(note, "<(-?%d*)>")
            if not dkp then
                dkp = 0  -- Значение по умолчанию если не удалось распарсить
            end
            T_Bidder_PlayerDKP = (1*dkp)  -- Конвертируем строку в число
        end
    end
    getglobal("T_BidderPlayerDKPButtonText"):SetText("Ваши очки ДКП: " .. T_Bidder_PlayerDKP)
end

-- Функция получения цвета класса по названию класса
function T_Bidder_GetClassColorCodes(classname)
    local colors = { 128,128,128 } -- серый по умолчанию (если класс не найден)
    local cc
    for n=1, table.getn(T_Bidder_CLASS_COLORS), 1 do
        cc = T_Bidder_CLASS_COLORS[n]
        if cc[1] == classname then
            return cc[2]  -- Возвращаем RGB цвет класса
        end
    end

    return colors  -- Возвращаем серый цвет по умолчанию
end

-- Функция разделения строки на слова (для парсинга аддон-сообщений)
function T_Bidder_SplitString(inputstr)
    local t={} ; i=1
    for w in string.gfind(inputstr, "%w+") do
        t[i] = w
        i = i + 1
    end
    return t
end
