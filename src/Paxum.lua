-- Paxum Extension (paxum.com) for MoneyMoney (moneymoney-app.com)
-- Fetches balances from Paxum and returns them as transactions

-- MIT License

-- Copyright (c) 2018 Philip Günther (Pag-Man)

-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:

-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.

-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

WebBanking {
    version = 1.1,
    url = "https://secure.paxum.com/payment/login.php?view=views/login.xsl",
    services = {
        "Paxum"
    },
    description = "Extension for Paxum"
}

local connection = nil
local mainPage = nil
local logoutUrl = "https://secure.paxum.com/payment/phrame.php?action=logout"

function SupportsBank(protocol, bankCode)
    return protocol == ProtocolWebBanking and bankCode == "Paxum"
end

function InitializeSession (protocol, bankCode, username, username2, password, username3)
    connection = Connection()

    print("Loading login page: " .. url)

    local loginPage = HTML(connection:get(url))

    loginPage:xpath("//input[@name='username']"):attr("value", username)
    loginPage:xpath("//input[@name='password']"):attr("value", password)

    print("Logging in...")

    mainPage = HTML(connection:request(loginPage:xpath("//form[@name='login']"):submit()))

    -- Check if we are actually logged in
    local financeOverview = mainPage:xpath("//*[@class='tableDataLabel']")
    if financeOverview:length() == 0 then
        return "Login failed. First check your credentials. Then try logging in on the browser, there might be an information page you have to confirm before you can login."
    end

    print("Login successful!")

    return nil
end


function ListAccounts (knownAccounts)
    print("Loading statements page...")

    local statementsPage = HTML(connection:get("https://secure.paxum.com/payment/journalEntryItemList.php?view=views/journalEntryItemList.xsl"))

    local accountsSelect = statementsPage:xpath("//select[@name='accountId']")

    local accounts = {}

    accountsSelect:children():each(
        function (i, accountsOption)
            local accountNumber = accountsOption:xpath("@value"):text()

            if accountNumber ~= "" then
                local currency = 'USD'
                local i = 1
                for match in string.gmatch(accountsOption:text(), "%S+") do
                    if i == 1 then
                        currency = match
                    end

                    i = i + 1
                end

                table.insert(accounts, {
                    name = "Paxum " .. currency,
                    accountNumber = accountNumber,
                    currency = currency
                })
            end
        end
    )

    return accounts
end

function RefreshAccount (account, since)
    print("Loading initial statements page...")

    local statementsPage = HTML(connection:get("https://secure.paxum.com/payment/journalEntryItemList.php?view=views/journalEntryItemList.xsl"))

    statementsPage:xpath("//select[@name='accountId']"):select(account.accountNumber)

    print("Loading the statement page for the account...")

    local statementPage = HTML(connection:request(statementsPage:xpath("//form[@name='searchForm']"):submit()))

    local balance = tonumber((statementPage:xpath("//table[@class='table'][1]/tr[2]/td[7]"):text():gsub(",", "")))

    local tableRows = statementPage:xpath("//table[@class='table'][1]/tr")

    local transactions = {}

    tableRows:each(
        function (i, tableRow)
            local amount = 0
            local debit = tonumber((tableRow:xpath("td[5]"):text():gsub(",", "")))
            local credit = tonumber((tableRow:xpath("td[6]"):text():gsub(",", "")))

            if debit ~= nil or credit ~= nil then
                if debit ~= nil and debit > 0 then
                    amount = -debit
                end

                if credit ~= nil and credit > 0 then
                    amount = credit
                end

                local year, month, day = string.match(tableRow:xpath("td[2]"):text(), "(%d%d%d%d).(%d%d).(%d%d)")

                table.insert(transactions, {
                    transactionCode = tableRow:xpath("td[1]"):text(),
                    bookingDate = os.time({
                        year = tonumber(year),
                        month = tonumber(month),
                        day = tonumber(day)
                    }),
                    purpose = tableRow:xpath("td[3]"):text(),
                    bookingText = tableRow:xpath("td[4]"):text(),
                    amount = amount
                })
            end
        end
    )

    return {
        balance = balance,
        transactions = transactions
    }
end

function EndSession()
    print("Logging out...")

    connection:get(logoutUrl)
end
