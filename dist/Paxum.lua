-- Paxum Extension (paxum.com) for MoneyMoney (moneymoney-app.com)
-- Fetches balances from Paxum and returns them as transactions

-- MIT License

-- Copyright (c) 2020 Philip Günther (Pac-Man)

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
    version = 2.0,
    url = "https://secure.paxum.com/payment/api/paymentAPI.php",
    services = {
        "Paxum"
    },
    description = "Extension for Paxum"
}

local connection = nil
local defaultParams = {}

function SupportsBank(protocol, bankCode)
    return protocol == ProtocolWebBanking and bankCode == "Paxum"
end

function SendApiRequest(params)
    -- Merge defaultParams with params
    for key, value in pairs(defaultParams) do
        params[key] = value
    end

    -- Build parameter string
    local postContent = ""

    for key, value in pairs(params) do
        if postContent ~= "" then
            postContent = postContent .. "&"
        end

        postContent = postContent .. key .. "=" .. value
    end

    local method = "POST"
    local postContentType = "application/x-www-form-urlencoded"

    local response = connection:request(method, url, postContent, postContentType)

    local xml = HTML(response)

    return xml
end

function InitializeSession (protocol, bankCode, username, username2, password, username3)
    connection = Connection()

    -- Define credentials
    defaultParams["fromEmail"] = username
    defaultParams["sharedSecret"] = password

    -- Login: https://eu.paxum.com/developers/api-documentation/miscellaneous-functions/login/
    local xml = SendApiRequest({
        method = "login",
        key = MM.md5(defaultParams["sharedSecret"] .. defaultParams["fromEmail"]):lower()
    })

    -- Check the response code
    if xml:xpath("//response/responsecode"):text() ~= "00" then
        return xml:xpath("//response/responsedescription"):text() .. ". Please use the username used during login on the web (example: your_name@domain.com) and the SharedSecret obtained from Merchant Services >> API Settings."
    end

    print("Login successful!")

    return nil
end

function ListAccounts (knownAccounts)
    -- Balance Inquiry: https://eu.paxum.com/developers/api-documentation/transaction-flow-and-content/balance-inquiry/
    local xml = SendApiRequest({
        method = "balanceInquiry",
        key = MM.md5(defaultParams["sharedSecret"]):lower()
    })

    -- Check the response code
    if xml:xpath("//response/responsecode"):text() ~= "00" then
        return xml:xpath("//response/responsedescription"):text() .. "."
    end

    local accounts = {}

    local xmlAccounts = xml:xpath("//response/accounts"):children()

    xmlAccounts:each(
        function (index, xmlAccount)
            table.insert(accounts, {
                name = xmlAccount:xpath("accountname"):text(),
                accountNumber = xmlAccount:xpath("accountid"):text(),
                currency = xmlAccount:xpath("currency"):text()
            })
        end
    )

    return accounts
end

function RefreshAccount (account, since)
    -- Balance Inquiry: https://eu.paxum.com/developers/api-documentation/transaction-flow-and-content/balance-inquiry/
    local xml = SendApiRequest({
        method = "balanceInquiry",
        accountId = account.accountNumber,
        key = MM.md5(defaultParams["sharedSecret"] .. account.accountNumber):lower()
    })

    -- Check the response code
    if xml:xpath("//response/responsecode"):text() ~= "00" then
        return xml:xpath("//response/responsedescription"):text() .. "."
    end

    local balance = xml:xpath("//response/accounts/account/balance"):text()

    -- Transaction History: https://eu.paxum.com/developers/api-documentation/transaction-flow-and-content/transaction-history/
    local fromDate = os.date('%Y-%m-%d', since)
    local toDate = os.date('%Y-%m-%d', os.time())
    local pageSize = 100
    local pageNumber = 1

    local xml = SendApiRequest({
        method = "transactionHistory",
        accountId = account.accountNumber,
        fromDate = fromDate,
        toDate = toDate,
        pageSize = pageSize,
        pageNumber = pageNumber,
        key = MM.md5(defaultParams["sharedSecret"] .. account.accountNumber .. fromDate .. toDate .. pageSize .. pageNumber):lower()
    })

    -- Check the response code
    if xml:xpath("//response/responsecode"):text() ~= "00" then
        return xml:xpath("//response/responsedescription"):text() .. "."
    end

    local transactions = {}

    local xmlTransactions = xml:xpath("//response/transactions"):children()

    xmlTransactions:each(
        function (index, xmlTransaction)
            local year, month, day = string.match(xmlTransaction:xpath("transactiondate"):text(), "(%d%d%d%d).(%d%d).(%d%d)")

            table.insert(transactions, {
                transactionCode = xmlTransaction:xpath("transactionid"):text(),
                bookingDate = os.time({
                    year = tonumber(year),
                    month = tonumber(month),
                    day = tonumber(day)
                }),
                purpose = xmlTransaction:xpath("description"):text(),
                amount = xmlTransaction:xpath("amount"):text(),
                currency = xmlTransaction:xpath("currency"):text()
            })
        end
    )

    return {
        balance = balance,
        transactions = transactions
    }
end

function EndSession()
    return nil
end

-- SIGNATURE: MCwCFEmVXpjIdx4rBuaiLSvDXdR/UZbBAhRgYkUSVZ+GWomcsWHMbl7iDlzkSA==
