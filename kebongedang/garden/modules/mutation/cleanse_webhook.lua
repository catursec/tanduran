--[[ webhook/cleanse.lua — webhook Automation Mutation (aura + cleanse).
     Dikirim saat pet target dapat mutasi "keep" (harvest). ]]
local cleanseWebhook = {}

function cleanseWebhook.sendObtained(ctx, petType, mutation, age, remainsQueue)
	local CFG = ctx.CFG
	if not CFG.webhookUrl or CFG.webhookUrl == "" then return end

	local payload = {
		embeds = {
			{
				title = "\240\159\140\177 Growth \226\128\162 Mutation",
				color = 3066993,
				fields = {
					{
						name = "Profile :",
						value = string.format("> Username : ||%s||", ctx.LP.Name),
						inline = false,
					},
					{
						name = "Mutation Obtained",
						value = string.format(
							"> Pet Type: `%s`\n" ..
							"> Mutation: `%s`\n" ..
							"> Age: `%s`\n" ..
							"> Remains Queue: `%s`",
							tostring(petType or "?"),
							tostring(mutation or "?"),
							tostring(age or 0),
							tostring(remainsQueue or 0)
						),
						inline = false,
					},
				},
				footer = {
					text = os.date("%B %d | %I:%M %p"),
					icon_url = "https://raw.githubusercontent.com/catursec/tanduran/main/kebongedang/Logo/logo_icon.png",
				},
			},
		},
	}
	if ctx.sendWebhook then ctx.sendWebhook(CFG.webhookUrl, payload, ctx) end
end

return cleanseWebhook
