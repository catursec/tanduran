--[[ services.lua — services + deps game (garden). ]]
return function(ctx)
	local Players     = game:GetService("Players")
	local RS          = game:GetService("ReplicatedStorage")
	local HttpService = game:GetService("HttpService")
	local UserInputService = game:GetService("UserInputService")

	if not game:IsLoaded() then game.Loaded:Wait() end
	repeat task.wait() until Players.LocalPlayer

	ctx.Services = {
		Players = Players, RS = RS, HttpService = HttpService, UserInputService = UserInputService,
	}
	ctx.LP = Players.LocalPlayer

	local DataService = require(RS.Modules.DataService)
	local PetEggs     = require(RS.Data.PetRegistry.PetEggs)
	local MutReg      = require(RS.Data.PetRegistry.PetMutationRegistry)
	local okPU, PU    = pcall(require, RS.Modules.PetServices.PetUtilities)

	-- TradingController singleton (buat baca state trade aktif)
	local okTC, TradingController = pcall(require, RS.Modules.TradeControllers.TradingController)

	local TradeEvents = RS.GameEvents.TradeEvents

	ctx.deps = {
		DataService      = DataService,
		PetEggs          = PetEggs,
		MutReg           = MutReg,
		EnumToMut        = MutReg.EnumToPetMutation,
		TradingController = okTC and TradingController or nil,

		TradeEvents   = TradeEvents,
		SendRequest   = TradeEvents.SendRequest,
		RespondRequest = TradeEvents.RespondRequest,
		AddItem       = TradeEvents.AddItem,
		RemoveItem    = TradeEvents.RemoveItem,
		Accept        = TradeEvents.Accept,
		Confirm       = TradeEvents.Confirm,
		Decline       = TradeEvents.Decline,
		FavoriteItem  = RS.GameEvents:FindFirstChild("Favorite_Item"),
		Gift          = RS.GameEvents:FindFirstChild("Gift"),
		-- Gift pet langsung (beda dari trade): GiftPet masuk, AcceptPetGift buat terima.
		GiftPet       = RS.GameEvents:FindFirstChild("GiftPet"),
		AcceptPetGift = RS.GameEvents:FindFirstChild("AcceptPetGift"),
		-- PNP (pick & place): PetsService("UnequipPet",uuid) / ("EquipPet",uuid,cframeStr)
		PetsService   = RS.GameEvents:FindFirstChild("PetsService"),
		PU            = okPU and PU or nil,
		-- cooldown skill: PetCooldownsUpdated(uuid, {{Time=,Passive=},...})
		PetCooldownsUpdated = RS.GameEvents:FindFirstChild("PetCooldownsUpdated"),
	}
end
