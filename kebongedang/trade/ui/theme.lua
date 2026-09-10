--[[ theme.lua — palet warna PINK ROYALE ELEGAN + helper pembuat Instance.
     Mengisi: ctx.C (warna), ctx.mk, ctx.corner, ctx.stroke, ctx.pad, ctx.grad ]]
return function(ctx)
	local C = {
		bg        = Color3.fromRGB(18, 10, 24),        -- Deep obsidian midnight plum / velvet rose
		panel     = Color3.fromRGB(28, 15, 36),        -- Dark luxury wine/mauve (sidebar & panel)
		row       = Color3.fromRGB(42, 22, 54),        -- Card container mewah
		rowAlt    = Color3.fromRGB(56, 30, 72),        -- Elevated card / dropdown item
		rowHover  = Color3.fromRGB(70, 36, 90),        -- Hover state card
		stroke    = Color3.fromRGB(255, 75, 155),      -- Radiant rose-pink border
		strokeSub = Color3.fromRGB(110, 52, 118),      -- Subtle border muted
		acc       = Color3.fromRGB(255, 50, 135),      -- Hot Radiant Rose (aksen utama)
		acc2      = Color3.fromRGB(255, 120, 195),     -- Soft Neon Sakura (gradient partner)
		accSoft   = Color3.fromRGB(255, 180, 225),     -- Pastel Rose Shimmer
		glow      = Color3.fromRGB(255, 60, 145),      -- Ambient glow
		txt       = Color3.fromRGB(255, 242, 252),     -- Pearl White Shimmer (teks utama ultra-tajam)
		sub       = Color3.fromRGB(215, 168, 212),     -- Soft Lavender-Rose (deskripsi terbaca jelas)
		green     = Color3.fromRGB(110, 245, 185),     -- Luminous Mint-Emerald
		red       = Color3.fromRGB(255, 65, 110),      -- Passion Crimson Rose
	}

	local F = {
		title = Enum.Font.FredokaOne,       -- Judul / Header / Branding (Modern & Segar, beda total dari Gotham)
		bold  = Enum.Font.MontserratBold,   -- Subheader / Tombol / Label Tebal (Tajam & Elegan)
		semi  = Enum.Font.MontserratMedium, -- Dropdown item / Value pill
		reg   = Enum.Font.Ubuntu,           -- Deskripsi & isi teks (Sangat nyaman dibaca)
		code  = Enum.Font.Code,             -- Console logs
	}

	local function mk(cls, props, parent)
		local o = Instance.new(cls)
		for k, v in pairs(props) do o[k] = v end
		o.Parent = parent
		return o
	end

	local function corner(o, r)
		return mk("UICorner", { CornerRadius = UDim.new(0, r or 10) }, o)
	end

	local function stroke(o, col, thick, trans)
		return mk("UIStroke", {
			Color = col or C.strokeSub,
			Thickness = thick or 1.2,
			Transparency = trans or 0.35,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, o)
	end

	local function pad(o, l, r, t, b)
		return mk("UIPadding", {
			PaddingLeft = UDim.new(0, l),
			PaddingRight = UDim.new(0, r),
			PaddingTop = UDim.new(0, t),
			PaddingBottom = UDim.new(0, b),
		}, o)
	end

	local function grad(o, rot, col1, col2)
		return mk("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, col1 or C.acc),
				ColorSequenceKeypoint.new(1, col2 or C.acc2),
			}),
			Rotation = rot or 90,
		}, o)
	end

	ctx.C      = C
	ctx.F      = F
	ctx.mk     = mk
	ctx.corner = corner
	ctx.stroke = stroke
	ctx.pad    = pad
	ctx.grad   = grad
end
