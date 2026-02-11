--[[
    T-Bidder for Turtle WoW
    Original author: Misha (Wht Mst)
    Based on: DKPAuctionBidder
    GitHub: https://github.com/whtmst/T-Bidder

    Аддон для участия в DKP аукционах в рейде.
    Отслеживает ставки, таймеры и результаты аукционов.
]] --


-- Настройка кириллического шрифта из папки аддона (только для внутреннего использования)
local T_Bidder_FontPath = "Interface\\AddOns\\T-Bidder\\Fonts\\ARIALN.ttf"

-- Идентификаторы аддона для коммуникации
local T_Bidder_Identifier = "TBidder"
local T_Bidder_SOTAprefix = "SOTAv1"

-- Проверка наличия pfUI
local T_Bidder_UseClassColors = IsAddOnLoaded("pfUI") or false

-- Ссылка на предмет текущего аукциона (для интеграции с SOTA)
local T_Bidder_AuctionItemLink = ""
local T_Bidder_AuctionItemID = 0

-- Переменные для отслеживания обновления информации о предмете
local T_Bidder_ItemInfoCheckTimer = 0
local T_Bidder_ItemInfoCheckInterval = 0.5  -- Проверять каждые 0.5 секунды

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
    ["DRUID"] = { 255,125, 10 },    -- оранжевый
    ["HUNTER"] = { 171,212,115 },   -- зеленый
    ["MAGE"] = { 105,204,240 },     -- голубой
    ["PALADIN"] = { 245,140,186 },  -- розовый
    ["PRIEST"] = { 255,255,255 },   -- белый
    ["ROGUE"] = { 255,245,105 },    -- желтый
    ["SHAMAN"] = { 0,112,222 },     -- синий
    ["WARLOCK"] = { 148,130,201 },  -- фиолетовый
    ["WARRIOR"] = { 199,156,110 }   -- коричневый
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
        T_Bidder_BidTimer = 0  -- Сбрасываем таймер, чтобы отсчет пошел заново

        -- Визуально отключаем кнопки
        getglobal("T_BidderBidMinButton"):Disable()
        getglobal("T_BidderBidMaxButton"):Disable()
        getglobal("T_BidderBidXButton"):Disable()
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
        T_Bidder_BidTimer = 0  -- Сбрасываем таймер, чтобы отсчет пошел заново

        -- Визуально отключаем кнопки
        getglobal("T_BidderBidMinButton"):Disable()
        getglobal("T_BidderBidMaxButton"):Disable()
        getglobal("T_BidderBidXButton"):Disable()
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
        T_Bidder_BidTimer = 0  -- Сбрасываем таймер, чтобы отсчет пошел заново

        -- Визуально отключаем кнопки
        getglobal("T_BidderBidMinButton"):Disable()
        getglobal("T_BidderBidMaxButton"):Disable()
        getglobal("T_BidderBidXButton"):Disable()
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
    T_Bidder_ItemInfoCheckTimer = T_Bidder_ItemInfoCheckTimer + elapsed

    -- Таймер между ставками (чтобы избежать спама)
    if T_Bidder_BidTimer > T_Bidder_SubmitBidTimer then
        T_Bidder_BidTimer = 0
        T_Bidder_SubmitBidFlag = 1  -- Разрешаем следующую ставку

        -- Включаем кнопки обратно
        getglobal("T_BidderBidMinButton"):Enable()
        getglobal("T_BidderBidMaxButton"):Enable()
        getglobal("T_BidderBidXButton"):Enable()
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

    -- Проверяем информацию о предмете, если она недоступна
    if T_Bidder_AuctionItemLink ~= "" and T_Bidder_ItemInfoCheckTimer > T_Bidder_ItemInfoCheckInterval then
        T_Bidder_CheckItemInfo()
        T_Bidder_ItemInfoCheckTimer = 0  -- Сбрасываем таймер
    end
end

-- Функция проверки информации о предмете и обновления отображения
function T_Bidder_CheckItemInfo()
    if T_Bidder_AuctionItemLink and T_Bidder_AuctionItemLink ~= "" then
        local _, _, itemID = string.find(T_Bidder_AuctionItemLink, "item:(%d+):")
        if itemID then
            -- Пытаемся получить информацию о предмете
            local itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture = GetItemInfo(itemID)

            if itemName then
                -- Информация о предмете теперь доступна, обновляем интерфейс
                local nameFrame = getglobal("T_BidderUIFrameItemItemName")
                if nameFrame then
                    nameFrame:SetText(itemName)

                    -- Устанавливаем цвет названия в зависимости от редкости
                    local qualityColors = {
                        [0] = {157, 157, 157},   -- Poor (Серый)
                        [1] = {255, 255, 255},   -- Common (Белый)
                        [2] = {30, 240, 30},     -- Uncommon (Зеленый)
                        [3] = {0, 112, 221},     -- Rare (Синий)
                        [4] = {163, 53, 238},    -- Epic (Фиолетовый)
                        [5] = {255, 128, 0},     -- Legendary (Оранжевый)
                        [6] = {230, 204, 128}    -- Artifact (Желтый)
                    }

                    local color = qualityColors[itemRarity] or qualityColors[1]
                    nameFrame:SetTextColor(color[1]/255, color[2]/255, color[3]/255, 1)
                end

                -- Информация успешно загружена, можно прекратить проверку
                T_Bidder_ItemInfoCheckTimer = 0
            end
        end
    end
end

-- Функция показа тултипа предмета при наведении мыши
function T_Bidder_ShowItemTooltipOnEnter()
    if T_Bidder_AuctionItemLink and T_Bidder_AuctionItemLink ~= "" then
        -- Проверяем, есть ли ID предмета
        if T_Bidder_AuctionItemID and T_Bidder_AuctionItemID > 0 then
            -- Используем ID предмета для создания гиперссылки
            local itemLink = "item:" .. T_Bidder_AuctionItemID .. ":0:0:0"

            -- Показываем тултип с информацией о предмете, прикрепленный к фрейму
            local itemFrame = getglobal("T_BidderUIFrameItem")
            GameTooltip:SetOwner(itemFrame, "ANCHOR_RIGHT")
            local success = pcall(function() GameTooltip:SetHyperlink(itemLink) end)

            if not success then
                -- Если SetHyperlink не сработал, пробуем использовать оригинальную строку
                local successOrig = pcall(function() GameTooltip:SetHyperlink(T_Bidder_AuctionItemLink) end)
                if not successOrig then
                    -- Если и это не сработало, показываем информацию из строки
                    local start, finish, itemNameFromLink = string.find(T_Bidder_AuctionItemLink, "%[(.+)%]")

                    GameTooltip:SetOwner(itemFrame, "ANCHOR_RIGHT")
                    if itemNameFromLink then
                        GameTooltip:SetText("Предмет: " .. itemNameFromLink, 1, 1, 1)
                    else
                        GameTooltip:SetText("Предмет", 1, 1, 1)
                    end
                    GameTooltip:AddLine("Информация о предмете недоступна", 1, 0.5, 0.5)
                    GameTooltip:AddLine("Предмет может быть недоступен на этом сервере", 1, 0.5, 0.5)
                    GameTooltip:AddLine("Попробуйте нажать на предмет в чате для загрузки информации", 1, 0.5, 0.5)
                    GameTooltip:Show()
                end
            end
        else
            -- Если ID неизвестен, пробуем использовать оригинальную строку
            local itemFrame = getglobal("T_BidderUIFrameItem")
            GameTooltip:SetOwner(itemFrame, "ANCHOR_RIGHT")
            local success = pcall(function() GameTooltip:SetHyperlink(T_Bidder_AuctionItemLink) end)

            if not success then
                -- Если SetHyperlink не сработал, показываем информацию из строки
                local start, finish, itemNameFromLink = string.find(T_Bidder_AuctionItemLink, "%[(.+)%]")

                GameTooltip:SetOwner(itemFrame, "ANCHOR_RIGHT")
                if itemNameFromLink then
                    GameTooltip:SetText("Предмет: " .. itemNameFromLink, 1, 1, 1)
                else
                    GameTooltip:SetText("Предмет", 1, 1, 1)
                end
                GameTooltip:AddLine("Информация о предмете недоступна", 1, 0.5, 0.5)
                GameTooltip:AddLine("Предмет может быть недоступен на этом сервере", 1, 0.5, 0.5)
                GameTooltip:AddLine("Попробуйте нажать на предмет в чате для загрузки информации", 1, 0.5, 0.5)
                GameTooltip:Show()
            end
        end
    else
        -- Показываем сообщение о том, что информация недоступна
        local itemFrame = getglobal("T_BidderUIFrameItem")
        GameTooltip:SetOwner(itemFrame, "ANCHOR_RIGHT")
        GameTooltip:SetText("Информация о предмете недоступна", 1, 0.5, 0.5)
        GameTooltip:AddLine("Предмет аукциона не определен", 1, 0.5, 0.5)
        GameTooltip:Show()
    end
end

-- Функция скрытия тултипа при уходе мыши
function T_Bidder_HideItemTooltipOnLeave()
    GameTooltip:Hide()
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
            local playerName = T_Bidder_Currentbid[4]
            if T_Bidder_UseClassColors then
                local color = T_Bidder_GetClassColorCodes(T_Bidder_Currentbid[5] or "Warrior")
                local coloredText = "Макс. ставка: " .. T_Bidder_Currentbid[3] .. " (|cff" ..
                                   string.format("%02x%02x%02x", color[1], color[2], color[3]) ..
                                   playerName .. "|r)"
                getglobal("T_BidderHighestBidTextButtonText"):SetText(coloredText)
            else
                local plainText = "Макс. ставка: " .. T_Bidder_Currentbid[3] .. " (" .. playerName .. ")"
                getglobal("T_BidderHighestBidTextButtonText"):SetText(plainText)
            end
            getglobal("T_BidderHighestBidTextButtonPlayer"):SetText("")
        elseif T_Bidder_AuctionState == 3 then
            getglobal("T_BidderHighestBidTextButtonText"):SetText("Аукцион приостановлен")
            getglobal("T_BidderHighestBidTextButtonPlayer"):SetText("")
        elseif T_Bidder_AuctionState == 4 then
            getglobal("T_BidderHighestBidTextButtonText"):SetText("Аукцион завершен (Ожидаем победителя)")
            getglobal("T_BidderHighestBidTextButtonPlayer"):SetText("")
        elseif T_Bidder_AuctionState == 5 then
            local playerName = T_Bidder_AuctionWinner
            if T_Bidder_UseClassColors then
                local color = T_Bidder_GetClassColorCodes(T_Bidder_AuctionWinnerClass or "Warrior")
                local coloredText = "Аукцион завершен (Победил - |cff" ..
                                   string.format("%02x%02x%02x", color[1], color[2], color[3]) ..
                                   playerName .. "|r)"
                getglobal("T_BidderHighestBidTextButtonText"):SetText(coloredText)
            else
                local plainText = "Аукцион завершен (Победил - " .. playerName .. ")"
                getglobal("T_BidderHighestBidTextButtonText"):SetText(plainText)
            end
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

    -- Синхронизация таймера по сообщениям чата (SotA)
    -- Это нужно, потому что аддон не присылает пакет синхронизации при продлении аукциона
    if string.find(msg, "SotA") and string.find(msg, "Осталось") then
        local _, _, seconds = string.find(msg, "Осталось (%d+) секун")
        if seconds then
            T_Bidder_AuctionTimeLeft = tonumber(seconds)
            -- Если таймер продлили, обновляем и общую длительность полосы
            if T_Bidder_AuctionTimeLeft > T_Bidder_AuctionTime then
                T_Bidder_AuctionTime = T_Bidder_AuctionTimeLeft
            end
        end
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

        -- Если аукцион еще не активен (State 0, 4, 5), ставим дефолтное время 30с.
        -- Если State = 1/2/3, значит аукцион уже запущен (например, через аддон с правильным временем),
        -- и мы не должны сбрасывать таймер.
        if T_Bidder_AuctionState == 0 or T_Bidder_AuctionState >= 4 then
            T_Bidder_AuctionTime = 30
            T_Bidder_AuctionTimeLeft = 30
        end

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
        -- Очищаем информацию о предмете аукциона и скрываем фрейм
        T_Bidder_AuctionItemLink = ""
        local itemFrame = getglobal("T_BidderUIFrameItem")
        if itemFrame then
            itemFrame:Hide()
        end
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
        -- Очищаем информацию о предмете аукциона и скрываем фрейм
        T_Bidder_AuctionItemLink = ""
        local itemFrame = getglobal("T_BidderUIFrameItem")
        if itemFrame then
            itemFrame:Hide()
        end
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
            local winnerName = playerName
            if T_Bidder_UseClassColors then
                local color = T_Bidder_GetClassColorCodes(T_Bidder_AuctionWinnerClass)
                local coloredText = "Аукцион завершен (Победил - |cff" ..
                                   string.format("%02x%02x%02x", color[1], color[2], color[3]) ..
                                   winnerName .. "|r)"
                getglobal("T_BidderHighestBidTextButtonText"):SetText(coloredText)
            else
                local plainText = "Аукцион завершен (Победил - " .. winnerName .. ")"
                getglobal("T_BidderHighestBidTextButtonText"):SetText(plainText)
            end
            getglobal("T_BidderHighestBidTextButtonPlayer"):SetText("")

            T_Bidder_AuctionState = 5 -- Финальное состояние: победитель объявлен
            -- Очищаем информацию о предмете аукциона и скрываем фрейм
            T_Bidder_AuctionItemLink = ""
            local itemFrame = getglobal("T_BidderUIFrameItem")
            if itemFrame then
                itemFrame:Hide()
            end
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
                local playerName = T_Bidder_LastHighestBid[4]
                if T_Bidder_UseClassColors then
                    local color = {1, 1, 1} -- белый по умолчанию
                    if T_Bidder_LastHighestBid[5] then
                        color = T_Bidder_GetClassColorCodes(T_Bidder_LastHighestBid[5])
                    end
                    local coloredText = "Макс. ставка: " .. T_Bidder_LastHighestBid[3] .. " (|cff" ..
                                       string.format("%02x%02x%02x", color[1], color[2], color[3]) ..
                                       playerName .. "|r)"
                    getglobal("T_BidderHighestBidTextButtonText"):SetText(coloredText)
                else
                    local plainText = "Макс. ставка: " .. T_Bidder_LastHighestBid[3] .. " (" .. playerName .. ")"
                    getglobal("T_BidderHighestBidTextButtonText"):SetText(plainText)
                end
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

            if T_Bidder_UseClassColors then
                local coloredText = prefix .. bidAmount .. " (|cff" ..
                                   string.format("%02x%02x%02x", classColor[1], classColor[2], classColor[3]) ..
                                   playerName .. "|r)"
                getglobal("T_BidderHighestBidTextButtonText"):SetText(coloredText)
            else
                local plainText = prefix .. bidAmount .. " (" .. playerName .. ")"
                getglobal("T_BidderHighestBidTextButtonText"):SetText(plainText)
            end
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

    -- Обработка сообщения с ссылкой на предмет от SOTA
    if prefix == "SOTA_ITEM_LINK" then
        -- Можно обновить интерфейс, чтобы показать предмет
        T_Bidder_UpdateItemDisplay(msg)


        -- Также можно обновить тултип при наведении на элемент интерфейса
        return  -- выходим, чтобы не обрабатывать дальше как обычное сообщение
    end

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
            local playerName = T_Bidder_Currentbid[4]
            if T_Bidder_UseClassColors then
                local color = T_Bidder_GetClassColorCodes(T_Bidder_Currentbid[5] or "Warrior")
                local coloredText = "Макс. ставка: " .. T_Bidder_Currentbid[3] .. " (|cff" ..
                                   string.format("%02x%02x%02x", color[1], color[2], color[3]) ..
                                   playerName .. "|r)"
                getglobal("T_BidderHighestBidTextButtonText"):SetText(coloredText)
            else
                local plainText = "Макс. ставка: " .. T_Bidder_Currentbid[3] .. " (" .. playerName .. ")"
                getglobal("T_BidderHighestBidTextButtonText"):SetText(plainText)
            end
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
            -- Очищаем информацию о предмете аукциона и скрываем фрейм
            T_Bidder_AuctionItemLink = ""
            local itemFrame = getglobal("T_BidderUIFrameItem")
            if itemFrame then
                itemFrame:Hide()
            end

        -- Пауза аукциона через SotA
        elseif msg == "SOTA_AUCTION_PAUSE" then
            getglobal("T_BidderHighestBidTextButtonText"):SetText("Аукцион приостановлен")
            getglobal("T_BidderHighestBidTextButtonPlayer"):SetText("")
            T_Bidder_AuctionStatePrePause = T_Bidder_AuctionState  -- Сохраняем состояние до паузы
            T_Bidder_AuctionState = 3  -- Устанавливаем состояние паузы

        -- Возобновление аукциона через SotA
        elseif string.find(msg, "SOTA_AUCTION_RESUME") == 1 then
            if T_Bidder_AuctionStatePrePause == 2 then
                local playerName = T_Bidder_LastHighestBid[4]
                if T_Bidder_UseClassColors then
                    local color = T_Bidder_GetClassColorCodes(T_Bidder_LastHighestBid[5] or "Warrior")
                    local coloredText = "Макс. ставка: " .. T_Bidder_LastHighestBid[3] .. " (|cff" ..
                                       string.format("%02x%02x%02x", color[1], color[2], color[3]) ..
                                       playerName .. "|r)"
                    getglobal("T_BidderHighestBidTextButtonText"):SetText(coloredText)
                else
                    local plainText = "Макс. ставка: " .. T_Bidder_LastHighestBid[3] .. " (" .. playerName .. ")"
                    getglobal("T_BidderHighestBidTextButtonText"):SetText(plainText)
                end
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
    -- Проверяем, есть ли classname и является ли он строкой
    if not classname or type(classname) ~= "string" then
        -- Возвращаем серый цвет по умолчанию в формате RGB
        return { 128, 128, 128 }
    end

    -- Преобразуем имя класса в верхний регистр для сравнения
    local upperClassName = string.upper(classname)

    -- Проверяем, есть ли такой класс в таблице
    if T_Bidder_CLASS_COLORS[upperClassName] then
        return T_Bidder_CLASS_COLORS[upperClassName]  -- Возвращаем RGB цвет класса
    else
        return { 128, 128, 128 }  -- Возвращаем серый цвет по умолчанию
    end
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

-- Функция обновления отображения предмета
function T_Bidder_UpdateItemDisplay(itemLink)
    -- Сохраняем оригинальную строку, которую SOTA отправил
    -- Она содержит полную item-ссылку с цветовыми кодами и может быть использована напрямую
    T_Bidder_AuctionItemLink = itemLink

    -- Извлекаем ID предмета из строки itemLink
    local _, _, itemID = string.find(itemLink, "item:(%d+):")
    if itemID then
        T_Bidder_AuctionItemID = tonumber(itemID)

        -- Пытаемся получить информацию о предмете
        local itemName, itemLinkResult, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture = GetItemInfo(itemID)

        if itemName then
            -- Информация о предмете уже в кэше, обновляем интерфейс
            local nameFrame = getglobal("T_BidderUIFrameItemItemName")
            if nameFrame then
                -- Обрезаем слишком длинные названия
                local displayName = T_Bidder_TruncateString(itemName, 40) -- Ограничиваем 40 символами
                nameFrame:SetText(displayName)

                -- Устанавливаем цвет названия в зависимости от редкости
                local qualityColors = {
                    [0] = {157, 157, 157},   -- Poor (Серый)
                    [1] = {255, 255, 255},   -- Common (Белый)
                    [2] = {30, 240, 30},     -- Uncommon (Зеленый)
                    [3] = {0, 112, 221},     -- Rare (Синий)
                    [4] = {163, 53, 238},    -- Epic (Фиолетовый)
                    [5] = {255, 128, 0},     -- Legendary (Оранжевый)
                    [6] = {230, 204, 128}    -- Artifact (Желтый)
                }

                local color = qualityColors[itemRarity] or qualityColors[1]
                nameFrame:SetTextColor(color[1]/255, color[2]/255, color[3]/255, 1)
            end
        else
            -- Пытаемся использовать tooltip для загрузки информации
            GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
            local success = pcall(function() GameTooltip:SetHyperlink("item:" .. itemID .. ":0:0:0") end)

            if success then
                -- Ждем немного, чтобы информация могла загрузиться
                -- и снова пробуем получить информацию
                local itemNameAfter, _, itemRarityAfter, _, _, _, _, _, _, itemTextureAfter = GetItemInfo(itemID)

                if itemNameAfter then
                    local nameFrame = getglobal("T_BidderUIFrameItemItemName")
                    if nameFrame then
                        -- Обрезаем слишком длинные названия
                        local displayName = T_Bidder_TruncateString(itemNameAfter, 40) -- Ограничиваем 40 символами
                        nameFrame:SetText(displayName)

                        local qualityColors = {
                            [0] = {157, 157, 157},   -- Poor (Серый)
                            [1] = {255, 255, 255},   -- Common (Белый)
                            [2] = {30, 240, 30},     -- Uncommon (Зеленый)
                            [3] = {0, 112, 221},     -- Rare (Синий)
                            [4] = {163, 53, 238},    -- Epic (Фиолетовый)
                            [5] = {255, 128, 0},     -- Legendary (Оранжевый)
                            [6] = {230, 204, 128}    -- Artifact (Желтый)
                        }

                        local color = qualityColors[itemRarityAfter] or qualityColors[1]
                        nameFrame:SetTextColor(color[1]/255, color[2]/255, color[3]/255, 1)
                    end
                else
                    -- Если не удалось получить информацию напрямую, извлекаем имя из строки
                    local start, finish, itemNameFromLink = string.find(itemLink, "%[(.+)%]")
                    if itemNameFromLink then
                        local nameFrame = getglobal("T_BidderUIFrameItemItemName")
                        if nameFrame then
                            -- Обрезаем слишком длинные названия
                            local displayName = T_Bidder_TruncateString(itemNameFromLink, 40) -- Ограничиваем 40 символами
                            nameFrame:SetText(displayName)
                            nameFrame:SetTextColor(1, 1, 1, 1) -- Белый цвет по умолчанию
                        end
                    end
                end
            else
                -- Если SetHyperlink не сработал, извлекаем имя из строки
                local start, finish, itemNameFromLink = string.find(itemLink, "%[(.+)%]")
                if itemNameFromLink then
                    local nameFrame = getglobal("T_BidderUIFrameItemItemName")
                    if nameFrame then
                        -- Обрезаем слишком длинные названия
                        local displayName = T_Bidder_TruncateString(itemNameFromLink, 40) -- Ограничиваем 40 символами
                        nameFrame:SetText(displayName)
                        nameFrame:SetTextColor(1, 1, 1, 1) -- Белый цвет по умолчанию
                    end
                end
            end
        end
    else
        -- Если не удалось извлечь ID, используем имя из строки
        local start, finish, itemNameFromLink = string.find(itemLink, "%[(.+)%]")
        if itemNameFromLink then
            local nameFrame = getglobal("T_BidderUIFrameItemItemName")
            if nameFrame then
                -- Обрезаем слишком длинные названия
                local displayName = T_Bidder_TruncateString(itemNameFromLink, 40) -- Ограничиваем 40 символами
                nameFrame:SetText(displayName)
                nameFrame:SetTextColor(1, 1, 1, 1) -- Белый цвет по умолчанию
            end
        end
    end

    -- Показываем фрейм предмета в любом случае
    local itemFrame = getglobal("T_BidderUIFrameItem")
    if itemFrame then
        itemFrame:Show()
    end
end

-- Функция для обрезки длинных строк
function T_Bidder_TruncateString(str, maxLength)
    if string.len(str) <= maxLength then
        return str
    end

    -- Проверяем, возможно строка содержит многобайтовые символы (кириллица)
    local length = 0
    local result = ""
    for i = 1, string.len(str) do
        local c = string.sub(str, i, i)
        result = result .. c
        length = length + 1
        if length >= maxLength then
            result = result .. "..."
            break
        end
    end
    return result
end
