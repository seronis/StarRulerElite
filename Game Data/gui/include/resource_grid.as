#include "~/Game Data/gui/include/gui_sprite.as"

const string@ rg_strMetl = "Metals", rg_strElec = "Electronics", rg_strAdvp = "AdvParts", rg_strOres = "Ore",  rg_strScrp = "Scrap";
const string@ rg_strFood = "Food",   rg_strFuel = "Fuel",        rg_strAmmo = "Ammo",     rg_strGuds = "Guds", rg_strLuxs = "Luxs";
const string@ rg_strLabr = "Labr";

enum ResourceIdentifier {
	SR_Advp,
	SR_Elec,
	SR_Metl,
	SR_Ores,
	SR_Scrp,
	SR_Labr,
	SR_Food,
	SR_Fuel,
	SR_Ammo,
	SR_Guds,
	SR_Luxs,
};

string@ _rg_standardize(float val) {
	if (abs(val) < 0.001f)
		return "0.00";
	else if (val < 0)
		return "-"+standardize(abs(val));
	else
		return standardize(val);
}

class ResourceGrid {
	GuiElement@ parent;
	GuiScripted@[] images;
	GuiStaticText@[] texts;
	uint columns;

	pos2di pos;
	dim2di cellSize;
	dim2di iconSize;
	dim2di offset;

	bool spaced;

	ResourceGrid(GuiElement@ Parent, pos2di position, uint cols) {
		spaced = false;
		@parent = Parent;
		columns = cols;
		pos = position;
		cellSize = dim2di(100, 17);
		iconSize = dim2di(14, 14);
	}

	ResourceGrid(GuiElement@ Parent, pos2di position, dim2di cell, uint cols) {
		spaced = false;
		@parent = Parent;
		columns = cols;
		pos = position;
		cellSize = cell;
		iconSize = dim2di(14, 14);
	}

	ResourceGrid(GuiElement@ Parent, pos2di position, dim2di cell, dim2di icon, uint cols) {
		spaced = false;
		@parent = Parent;
		columns = cols;
		pos = position;
		cellSize = cell;
		iconSize = icon;
	}

	~ResourceGrid() {
		clear();
	}

	void setSpaced(bool newSpaced) {
		spaced = newSpaced;
	}

	void clear() {
		for (uint i = 0; i < images.length(); ++i) {
			images[i].remove();
			texts[i].remove();
		}

		images.resize(0);
		texts.resize(0);
	}

	ScriptedGuiHandler@ getIcon(ResourceIdentifier res) {
		switch(res) {
			case SR_Advp: return gui_sprite("planet_resource_list", 0);
			case SR_Elec: return gui_sprite("planet_resource_list", 1);
			case SR_Metl: return gui_sprite("planet_resource_list", 2);
			case SR_Labr: return gui_sprite("planet_resource_list", 3);
			case SR_Fuel: return gui_sprite("planet_resource_list", 5);
			case SR_Ammo: return gui_sprite("planet_resource_list", 6);
		}
		return gui_sprite("planet_resource_list", 0);
	}

	string@ getToolTip(ResourceIdentifier res) {
		switch(res) {
			case SR_Advp: return localize("#advancedparts");
			case SR_Elec: return localize("#electronics");
			case SR_Metl: return localize("#metals");
			case SR_Labr: return localize("#labr");
			case SR_Fuel: return localize("#fuel");
			case SR_Ammo: return localize("#ammo");
		}
		return "";
	}

	void addDefaults(bool singleVal) {
		if (singleVal) {
			add(SR_Advp, 0);
			add(SR_Elec, 0);
			add(SR_Metl, 0);
			add(SR_Labr, 0);
			add(SR_Fuel, 0);
			add(SR_Ammo, 0);
		}
		else {
			add(SR_Advp, 0, 0);
			add(SR_Elec, 0, 0);
			add(SR_Metl, 0, 0);
			add(SR_Labr, 0, 0);
			add(SR_Fuel, 0, 0);
			add(SR_Ammo, 0, 0);
		}
	}

	void updateDefaults(const subSystem@ sys) {
		update(SR_Advp, sys.getCost(rg_strAdvp));
		update(SR_Elec, sys.getCost(rg_strElec));
		update(SR_Metl, sys.getCost(rg_strMetl));
		update(SR_Labr, sys.getCost(rg_strLabr));
		update(SR_Fuel, sys.getCost(rg_strFuel));
		update(SR_Ammo, sys.getCost(rg_strAmmo));
	}

	void updateDefaults(const HullStats@ stats) {
		update(SR_Advp, stats.getCost(rg_strAdvp));
		update(SR_Elec, stats.getCost(rg_strElec));
		update(SR_Metl, stats.getCost(rg_strMetl));
		update(SR_Labr, stats.getCost(rg_strLabr));
		update(SR_Fuel, stats.getCost(rg_strFuel));
		update(SR_Ammo, stats.getCost(rg_strAmmo));
	}

	void setVisible(bool visible) {
		for (uint i = 0; i < images.length(); ++i) {
			images[i].setVisible(visible);
			texts[i].setVisible(visible);
		}
	}

	string@ format(float val) {
		return _rg_standardize(val);
	}

	string@ format(float val, float max) {
		return combine(_rg_standardize(val), spaced ? " / " : "/", _rg_standardize(max));
	}

	uint add(ResourceIdentifier res, float val, float max) {
		uint i = add(getIcon(res), format(val, max));
		images[i].setToolTip(getToolTip(res));
		return i;
	}

	uint add(ResourceIdentifier res, float val) {
		uint i = add(getIcon(res), format(val));
		images[i].setToolTip(getToolTip(res));
		return i;
	}

	uint add(ScriptedGuiHandler@ img, string@ ttip, float val, float max) {
		uint i = add(img, format(val, max));
		images[i].setToolTip(ttip);
		return i;
	}

	uint add(ScriptedGuiHandler@ img, string@ ttip, float val) {
		uint i = add(img, format(val));
		images[i].setToolTip(ttip);
		return i;
	}

	uint add(ScriptedGuiHandler@ img, float val, float max) {
		uint i = add(img, format(val, max));
		return i;
	}

	uint add(ScriptedGuiHandler@ img, float val) {
		uint i = add(img, format(val));
		return i;
	}

	uint add(ScriptedGuiHandler@ img, string@ text) {
		uint n = images.length();
		images.resize(n+1);
		texts.resize(n+1);

		uint y = n / columns;
		uint x = n % columns;

		pos2di cellOffset(offset.width * x, offset.height * y);
		pos2di cellPos = pos2di(cellOffset.x + pos.x + cellSize.width * x, cellOffset.y + pos.y + cellSize.height * y);
		pos2di iconPos = pos2di(cellPos.x, cellPos.y + cellSize.height - iconSize.height);
		pos2di textPos = pos2di(cellPos.x + iconSize.width + 6, cellPos.y);

		dim2di textSize = dim2di(cellSize.width - iconSize.width - 12, cellSize.height);

		@images[n] = GuiScripted(recti(iconPos, iconSize), img, parent);
		@texts[n] = GuiStaticText(recti(textPos, textSize), text, false, false, false, parent);
		return n;
	}

	void reposition() {
		uint cnt = images.length();
		for (uint n = 0; n < cnt; ++n) {
			uint y = n / columns;
			uint x = n % columns;

			pos2di cellOffset(offset.width * x, offset.height * y);
			pos2di cellPos = pos2di(cellOffset.x + pos.x + cellSize.width * x, cellOffset.y + pos.y + cellSize.height * y);
			pos2di iconPos = pos2di(cellPos.x, cellPos.y + cellSize.height - iconSize.height);
			pos2di textPos = pos2di(cellPos.x + iconSize.width + 6, cellPos.y);

			dim2di textSize = dim2di(cellSize.width - iconSize.width - 12, cellSize.height);

			images[n].setPosition(iconPos);
			images[n].setSize(iconSize);

			texts[n].setPosition(textPos);
			texts[n].setSize(textSize);
		}
	}

	void setPosition(pos2di newPos) {
		pos = newPos;
		reposition();
	}

	void setCellSize(dim2di newSize) {
		cellSize = newSize;
		reposition();
	}

	void setOffset(dim2di newOffset) {
		offset = newOffset;
		reposition();
	}

	void update(uint i, float val, float max) {
		update(i, format(val, max));
	}

	void update(uint i, float val) {
		update(i, format(val));
	}

	void update(uint i, string@ text) {
		texts[i].setText(text);
	}
};
