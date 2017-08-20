#include "~/Game Data/gui/include/dialog.as"
#include "~/Game Data/gui/include/gui_skin.as"
#include "~/Game Data/gui/include/pl_queue.as"
#include "~/Game Data/gui/include/cqueue_saveload.as"
#include "~/Game Data/gui/include/resource_grid.as"
#include "~/Game Data/gui/include/objlist_unique.as"
#include "~/Game Data/gui/include/blueprints_sort.as"

import recti makeScreenCenteredRect(const dim2di &in rectSize) from "gui_lib";
import int getPlanetIconIndex(string@ physicalType) from "planet_icons";
import void triggerContextMenu(Object@) from "context_menu";

/* {{{ Constants */
const int MIN_WIDTH = 768;
const int MIN_HEIGHT = 512;

const float unitsPerAU = 1000.f;
const float econUpdateLength = 1.f;

const float syncDelay = 0.333f;
const float queueCheckDelay = 1.f;

const string@ strAdvpGen = "AdvpGen", strAdvp = "AdvParts";
const string@ strElecGen = "ElecGen", strElec = "Electronics";
const string@ strMetlGen = "MetlGen", strMetl = "Metals";
const string@ strOresGen = "OresGen", strOres = "Ore";
const string@ strScrpGen = "ScrpGen", strScrp = "Scrap";
const string@ strFoodGen = "FoodGen", strFood = "Food";
const string@ strFuelGen = "FuelGen", strFuel = "Fuel";
const string@ strAmmoGen = "AmmoGen", strAmmo = "Ammo";
const string@ strGudsGen = "GudsGen", strGuds = "Guds";
const string@ strLuxsGen = "LuxsGen", strLuxs = "Luxs";

const string@ strDeep = "DeepOre", strLabor = "Labr", strWorkers = "Workers", strMood = "Mood";
const string@ strDamage = "Damage";

const string@ strUnique = "Unique";

const string@ strDisableCivilActs = "disable_civil_acts", strFastConsumption = "fast_consumption", strNoFood = "no_food";
const string@ actShortWorkWeek = "work_low", actForcedLabor = "work_forced", actTaxBreak = "tax_break";
const string@ strLowLuxuries = "low_luxuries_consumption", strHighLuxuries = "high_luxuries_consumption";
const string@ strIndifferent = "forever_indifferent";
const string@ strTrade = "Trade", strTradeMode = "TradeMode";
const double million = 1000000.0;

const string[] shipTooltipHints = {"Armor", "Shield", "Thrust", "Fuel", "ShipBay"};
uint shipTooltipHintCount = 5;
/*
string@[] resNames =   { "#advparts",    "#electronics", "#metals",      "#food",
                         "#goods",       "#luxuries",    "#fuel",        "#ammo"      };
uint[] resColors =     {  0xffc2e4ff,     0xfff6ff00,     0xffeaeaea,     0xff197b30,
                          0xff987433,     0xffffb9b9,     0xffff8000,     0xffaaaaaa  };
*/
string@[] resNames =   { "#advparts",     "#electronics", "#metals",      "#ore",         "#scrap",
                         "#food",         "#fuel",        "#ammo",        "#goods",       "#luxuries",   };
uint[] resColors =     {  0xffffffff,     0xffffffff,     0xffffffff,     0xffffffff,     0xffffffff,
                          0xffffffff,     0xffffffff,     0xffffffff,     0xffffffff,     0xffffffff     };
						  
/* }}} */
/* {{{ Planet Window Handle */
class PlanetWindowHandle {
	PlanetWindow@ script;
	GuiScripted@ ele;

	PlanetWindowHandle(recti Position) {
		@script = PlanetWindow();
		@ele = GuiScripted(Position, script, null);

		script.init(ele);
		script.syncPosition(Position.getSize());
	}

	void setPlanet(Planet@ pl) {
		script.setPlanet(pl);
	}

	Planet@ getPlanet() {
		return script.getPlanet();
	}

	void findPlanet() {
		EmpireObjects objects;
		objects.prepare(getActiveEmpire());

		for (uint i = 0; i < objects.getCount(); ++i) {
			Planet@ planet = objects.getObject();

			if (@planet != null) {
				setPlanet(planet);
				break;
			}
		}
	}

	bool isPinned() {
		return script.isPinned();
	}

	void setPinned(bool pin) {
		script.setPinned(pin);
	}

	void bringToFront() {
		ele.bringToFront();
		setGuiFocus(ele);
		bindEscapeEvent(ele);
	}

	void setVisible(bool vis) {
		ele.setVisible(vis);

		if (vis)
			bindEscapeEvent(ele);
		else
			clearEscapeEvent(ele);
	}

	bool isVisible() {
		return ele.isVisible();
	}

	pos2di getPosition() {
		return ele.getPosition();
	}

	void update(float time) {
		script.update(time);
		script.position = ele.getPosition();
	}

	void remove() {
		clearEscapeEvent(ele);
		ele.remove();
		script.removed = true;
	}
};

/* }}} */
/* {{{ Planet Window Script */
class PlanetWindow : ScriptedGuiHandler {
	DragResizeInfo drag;
	pos2di position;
	bool removed;
	bool pinned;

	Planet@ planet;

	PlanetWindow() {
		removed = false;
		pinned = false;
	}

	void setPlanet(Planet@ pl) {
		@planet = pl;
		onPlanetChange(pl);
	}

	Planet@ getPlanet() {
		return planet;
	}

	/* {{{ Main interface */
	GuiButton@ close;

	// * Top Panel
	GuiPanel@ topPanel;
	GuiButton@ queueTab;
	GuiButton@ structsTab;
	GuiButton@ econTab;

	GuiButton@ nextButton;
	GuiButton@ prevButton;

	GuiButton@ zoomButton;
	GuiButton@ planetIco;

	GuiComboBox@ governor;
	GuiCheckBox@ useGovernor;

	GuiImage@ pinImg;

	GuiStaticText@ blockadedText;
	GuiStaticText@ name;
	GuiStaticText@ structuresText;
	GuiStaticText@ noConditionText;
	GuiExtText@[] conditions;
	ResourceGrid@ resources;

	// * Queue tab
	GuiPanel@ queuePanel;
	GuiListBox@ structureBuildList;
	GuiListBox@ shipBuildList;

	GuiStaticText@ queueName;
	GuiButton@ clearQueueButton;
	GuiButton@ saveQueueButton;
	GuiButton@ loadQueueButton;
	GuiButton@ repeatButton;
	GuiButton@ pauseButton;

	GuiButton@ buildShipsTab;
	GuiButton@ buildStructsTab;

	GuiListBox@ buildShipsList;
	GuiListBox@ buildStructsList;
	GuiComboBox@ shipSort;

	ResourceGrid@ activeCost;
	ResourceGrid@ totalCost;

	GuiStaticText@ totalText;

	GuiPanel@ hb_panel;
	GuiExtText@ hovered_build_panel;
	ResourceGrid@ hovered_cost;

	GuiScripted@ queueEle;
	pl_queue@ planet_queue;

	uint lastQueueSize;
	float progress;
	bool repeat;
	bool pause;
	bool blockaded;

	float syncTimer;
	float queueCheckTime;

	int buildingStructures;
	bool canBuildStructures;

	uint lastBuildables;
	int[] buildIDs;
	SortedBlueprintList layouts;

	// * Structures tab
	GuiPanel@ structsPanel;
	GuiButton@ removeStructButton;
	GuiButton@ renovateStructButton;

	GuiListBox@ structsList;
	GuiExtText@ structureInfo;

	uint prevStructGroups;
	dictionary structures;
	dictionary levels;

	// * Economy tab
	GuiPanel@ econPanel;
	GuiStaticText@ econ_popmult;
	GuiStaticText@ econ_moodmult;
	GuiStaticText@ econ_workersmult;
	GuiStaticText@ econ_pop;
	GuiStaticText@ econ_trade;

	GuiCheckBox@ allowImport;
	GuiCheckBox@ allowExport;

	GuiStaticText@[] economyValues;

	float econUpdateTick;

	void init(GuiElement@ ele) {
		economyValues.resize(7*10);
		syncTimer = 0.f;
		queueCheckTime = 0.f;
		buildingStructures = 0;
		econUpdateTick = 0.f;
		resetRates();

		lastBuildables = 0;
		prevStructGroups = 0;

		lastQueueSize = 0;
		progress = -1.f;
		repeat = false;
		pause = false;
		blockaded = false;
		canBuildStructures = true;

		@close = CloseButton(recti(), ele);

		// * Create top panel
		@topPanel = GuiPanel(recti(0, 20, 400, 70), false, SBM_Invisible, SBM_Invisible, ele);
		topPanel.fitChildren();

		// Top panel information
		@name = GuiStaticText(recti(pos2di(120, 2), dim2di(400, 20)), null, false, false, false, topPanel);
		name.setFont("stroked_subtitle");

		@planetIco = GuiButton(recti(pos2di(7, 2), dim2di(92, 92)), null, topPanel);
		planetIco.setAppearance(BA_ScaleImage, BA_Background);

		@zoomButton = GuiButton(recti(pos2di(0, 0), dim2di(16, 16)), null, topPanel);
		zoomButton.setImage("clause_edit");
		zoomButton.setAppearance(0, BA_Background);

		@structuresText = GuiStaticText(recti(0, 0, 140, 20), null, false, false, false, topPanel);
		structuresText.setTextAlignment(EA_Right, EA_Center);

		@blockadedText = GuiStaticText(recti(0, 0, 200, 20), localize("#MO_Blockade"), false, false, false, topPanel);
		blockadedText.setTextAlignment(EA_Center, EA_Center);
		blockadedText.setColor(Color(0xffff4444));
		blockadedText.setToolTip(localize("#MOTT_Blockade"));

		@governor = GuiComboBox(recti(pos2di(125 + 7, 41 + 19), dim2di(180, 20)), ele);
		@useGovernor = GuiCheckBox(false, recti(pos2di(125, 63), dim2di(200, 22)), localize("#PL_USE_GOVERNOR"), topPanel);

		@nextButton = Button(dim2di(100, 21), localize("#PL_NEXT"), topPanel);
		nextButton.setToolTip(localize("#PLTT_Next"));

		@noConditionText = GuiStaticText(recti(pos2di(125, 40), dim2di(240, 20)), localize("#PL_NoConditions"), false, false, false, topPanel);
		noConditionText.setFont("italic");

		@prevButton = Button(dim2di(100, 21), localize("#PL_PREVIOUS"), topPanel);
		prevButton.setToolTip(localize("#PLTT_Previous"));

		@pinImg = GuiImage(pos2di(320, 5), "planet_queuepin", topPanel);
		pinImg.setColor(pinned ? pinnedCol : unpinnedCol);
		pinImg.setClickThrough(false);
		pinImg.setToolTip(localize("#PL_Pin"));

		@resources = ResourceGrid(topPanel, pos2di(7, 103), 6);
		resources.iconSize = dim2di(17, 17);
		resources.add(gui_sprite("planet_topbar_resources", 0), localize("#PLTT_Food"), 0, 0);
		resources.add(gui_sprite("planet_topbar_resources", 1), localize("#PLTT_Deep"), 0);
		resources.add(gui_sprite("planet_topbar_resources", 2), localize("#PLTT_Damage"), 0);
		resources.add(gui_sprite("planet_topbar_resources", 3), localize("#PLTT_Labor"), 0, 0);
		resources.add(gui_sprite("planet_topbar_resources", 4), localize("#PLTT_Workers"), 0, 0);
		resources.add(gui_sprite("planet_topbar_resources", 5), localize("#PLTT_Mood"), 0, 1);

		// Tabs
		@queueTab   = TabButton(recti(), localize("#PL_MANAGE_QUEUE"), topPanel);
		@structsTab = TabButton(recti(), localize("#PL_STRUCTURES"), topPanel);
		@econTab    = TabButton(recti(), localize("#PL_Economy"), topPanel);

		queueTab.setPressed(true);

		// * Create queue tab
		@queuePanel = GuiPanel(recti(0, 20, 200, 70), false, SBM_Invisible, SBM_Invisible, ele);
		queuePanel.fitChildren();

		@planet_queue = pl_queue();
		@queueEle = GuiScripted(recti(), planet_queue, queuePanel);
		planet_queue.init(queueEle);

		@queueName = GuiStaticText(recti(), localize("#PL_NOTHING"), false, false, false, queuePanel);

		// Hover information
		@hb_panel = GuiPanel(recti(), true, SBM_Invisible, SBM_Invisible, queuePanel);
		@hovered_build_panel = GuiExtText(recti(pos2di(5,3), dim2di(50, 50)), hb_panel);
		hb_panel.setOverrideColor(Color(0xff000000));
		hb_panel.setVisible(false);

		@hovered_cost = ResourceGrid(hb_panel, pos2di(10, 170), dim2di(74, 17), 4);
		hovered_cost.addDefaults(true);

		// Queue build lists
		@buildShipsTab = TabButton(recti(105, 1, 209, 19), localize("#PL_BuildShips"), queuePanel);
		buildShipsTab.setToolTip(localize("#PLTT_BuildShips"));

		@buildStructsTab = TabButton(recti(1, 1, 105, 19), localize("#PL_BuildStructures"), queuePanel);
		buildStructsTab.setToolTip(localize("#PLTT_BuildStructures"));
		buildStructsTab.setPressed(true);

		@buildShipsList = GuiListBox(recti(0, 24, 0, 0), true, queuePanel);
		@buildStructsList = GuiListBox(recti(0, 24, 0, 0), true, queuePanel);
		buildShipsList.setVisible(false);

		@shipSort = GuiComboBox(recti(), queuePanel);
		shipSort.setVisible(false);

		shipSort.addItem("-- "+localize("#asc")+" --");
		shipSort.addItem(localize("#LET_SortName"));
		shipSort.addItem(localize("#LET_SortScale"));

		shipSort.addItem("-- "+localize("#desc")+" --");
		shipSort.addItem(localize("#LET_SortName"));
		shipSort.addItem(localize("#LET_SortScale"));

		shipSort.setSelected(2);

		@activeCost = ResourceGrid(queuePanel, pos2di(), 2);
		activeCost.setSpaced(true);
		activeCost.setCellSize(dim2di(112, 17));
		activeCost.setOffset(dim2di(0, 4));

		activeCost.add(SR_AdvParts, 0, 0);
		activeCost.add(SR_Metals, 0, 0);
		activeCost.add(SR_Electronics, 0, 0);
		activeCost.add(SR_Labor, 0, 0);

		activeCost.update(0, "---");
		activeCost.update(1, "---");
		activeCost.update(2, "---");
		activeCost.update(3, "---");

		@totalText = GuiStaticText(recti(0, 0, 173, 20), localize("#PL_TotalCost"), false, false, false, queuePanel);
		totalText.setTextAlignment(EA_Center, EA_Center);

		@totalCost = ResourceGrid(queuePanel, pos2di(), 2);
		totalCost.setCellSize(dim2di(86, 17));
		totalCost.setOffset(dim2di(0, 4));
		totalCost.add(SR_AdvParts, 0);
		totalCost.add(SR_Metals, 0);
		totalCost.add(SR_Electronics, 0);
		totalCost.add(SR_Labor, 0);

		// Queue actions
		@clearQueueButton = Button(dim2di(173, 22), localize("#PL_CLEAR_QUEUE"), queuePanel);
		@saveQueueButton = Button(dim2di(173, 22), localize("#PL_SAVE_QUEUE"), queuePanel);
		@loadQueueButton = Button(dim2di(173, 22), localize("#PL_LOAD_QUEUE"), queuePanel);

		@pauseButton = ToggleButton(false, dim2di(87, 22), localize("#PL_Pause"), queuePanel);
		@repeatButton = ToggleButton(false, dim2di(87, 22), localize("#PL_Repeat"), queuePanel);

		// * Create structures tab
		@structsPanel = GuiPanel(recti(0, 20, 200, 70), false, SBM_Invisible, SBM_Invisible, ele);
		structsPanel.fitChildren();
		structsPanel.setVisible(false);

		@structsList = GuiListBox(recti(0, 0, 259, 100), true, structsPanel);
		@structureInfo = GuiExtText(recti(274, 8, 100, 100), structsPanel);

		@removeStructButton = Button(dim2di(129, 22), localize("#PL_REMOVE_STRUCT"), structsPanel);
		@renovateStructButton = Button(dim2di(130, 22), localize("#PL_REBUILD_STRUCT"), structsPanel);
		renovateStructButton.setToolTip(localize("#PLTT_REBUILD_STRUCT"));

		// * Create economy tab
		@econPanel = GuiPanel(recti(0, 20, 200, 70), false, SBM_Invisible, SBM_Invisible, ele);
		econPanel.fitChildren();
		econPanel.setVisible(false);

		// Economy tab
		GuiStaticText@ txt;

		// Variable headers
		@txt = GuiStaticText(recti(pos2di(12, 12), dim2di(170, 18)), localize("#PL_PopMult"), false, false, false, econPanel);
		@econ_popmult = GuiStaticText(recti(pos2di(200, 12), dim2di(140, 18)), null, false, false, false, econPanel);
		txt.setToolTip(localize("#PLTT_PopMult"));
		txt.orphan(true);

		@txt = GuiStaticText(recti(pos2di(12, 32), dim2di(170, 18)), localize("#PL_MoodMult"), false, false, false, econPanel);
		@econ_moodmult = GuiStaticText(recti(pos2di(200, 32), dim2di(140, 18)), null, false, false, false, econPanel);
		txt.setToolTip(localize("#PLTT_MoodMult"));
		txt.orphan(true);

		@txt = GuiStaticText(recti(pos2di(12, 52), dim2di(170, 18)), localize("#PL_WorkersMult"), false, false, false, econPanel);
		@econ_workersmult = GuiStaticText(recti(pos2di(200, 52), dim2di(140, 18)), null, false, false, false, econPanel);
		txt.setToolTip(localize("#PLTT_WorkersMult"));
		txt.orphan(true);

		@txt = GuiStaticText(recti(pos2di(335, 12), dim2di(170, 18)), localize("#PL_Population"), false, false, false, econPanel);
		@econ_pop = GuiStaticText(recti(pos2di(553, 12), dim2di(140, 18)), null, false, false, false, econPanel);
		txt.setToolTip(localize("#PLTT_Population"));
		txt.orphan(true);

		@txt = GuiStaticText(recti(pos2di(335, 32), dim2di(170, 18)), localize("#PL_TradeUsed"), false, false, false, econPanel);
		@econ_trade = GuiStaticText(recti(pos2di(553, 32), dim2di(140, 18)), null, false, false, false, econPanel);
		txt.setToolTip(localize("#PLTT_TradeUsed"));
		txt.orphan(true);

		@allowImport = GuiCheckBox(true, recti(pos2di(345, 53), dim2di(135, 18)), localize("#PL_AllowImport"), econPanel);
		allowImport.setToolTip(localize("#PLTT_AllowImport"));

		@allowExport = GuiCheckBox(true, recti(pos2di(543, 53), dim2di(135, 18)), localize("#PL_AllowExport"), econPanel);
		allowExport.setToolTip(localize("#PLTT_AllowExport"));

		// Create economy headers
		@txt = GuiStaticText(recti(pos2di(130, 92), dim2di(120, 20)), localize("#PL_Storage"), false, false, false, econPanel);
		txt.setToolTip(localize("#PLTT_Storage"));
		txt.orphan(true);

		@txt = GuiStaticText(recti(pos2di(230, 92), dim2di(105, 20)), localize("#PL_Production"), false, false, false, econPanel);
		txt.setToolTip(localize("#PLTT_Production"));
		txt.orphan(true);
		txt.setTextAlignment(EA_Right, EA_Top);

		@txt = GuiStaticText(recti(pos2di(345, 92), dim2di(105, 20)), localize("#PL_Consumption"), false, false, false, econPanel);
		txt.setToolTip(localize("#PLTT_Consumption"));
		txt.orphan(true);
		txt.setTextAlignment(EA_Right, EA_Top);

		@txt = GuiStaticText(recti(pos2di(460, 92), dim2di(105, 20)), localize("#PL_Trade"), false, false, false, econPanel);
		txt.setToolTip(localize("#PLTT_Trade"));
		txt.orphan(true);
		txt.setTextAlignment(EA_Right, EA_Top);

		@txt = GuiStaticText(recti(pos2di(575, 92), dim2di(105, 20)), localize("#PL_NetChange"), false, false, false, econPanel);
		txt.setToolTip(localize("#PLTT_NetChange"));
		txt.orphan(true);
		txt.setTextAlignment(EA_Right, EA_Top);

		// Create economy data fields
		for (uint i = 0; i < 10; ++i) {
			GuiStaticText@ text = GuiStaticText(recti(pos2di(12, 128+(20*i)), dim2di(60, 20)), null, false, false, false, econPanel);
			text.setText(localize(resNames[i]));
			text.setColor(Color(resColors[i]));
			@economyValues[(i*7)] = text;

		//	if (i < 4 || i > 5) {
				@text = GuiStaticText(recti(pos2di(130, 128+(20*i)), dim2di(40, 20)), null, false, false, false, econPanel);
				text.setTextAlignment(EA_Right, EA_Top);
				@economyValues[(i*7)+1] = text;

				@text = GuiStaticText(recti(pos2di(175, 128+(20*i)), dim2di(10, 20)), "/", false, false, false, econPanel);
				text.orphan(true);

				@text = GuiStaticText(recti(pos2di(180, 128+(20*i)), dim2di(40, 20)), null, false, false, false, econPanel);
				text.setTextAlignment(EA_Right, EA_Top);
				@economyValues[(i*7)+2] = text;
		//	}

			for (uint h = 0; h < 4; ++h) {
				@text = GuiStaticText(recti(pos2di(230+(115*h), 128+(20*i)), dim2di(105, 20)), null, false, false, false, econPanel);
				text.setTextAlignment(EA_Right, EA_Top);

				@economyValues[(i*7)+h+3] = text;
			}
		}
	}

	void setPinned(bool pin) {
		pinned = pin;
		pinImg.setColor(pin ? pinnedCol : unpinnedCol);
	}

	bool isPinned() {
		return pinned;
	}

	void syncPosition(dim2di size) {
		// Close button
		close.setPosition(pos2di(size.width-30, 0));
		close.setSize(dim2di(30, 12));

		// Position top panel
		topPanel.setPosition(pos2di(7, 19));
		topPanel.setSize(dim2di(size.width - 7, 150));

		// Position right aligned top elements
		int topWidth = topPanel.getSize().width;
		name.setSize(dim2di(topWidth - 140 - 440, 20));
		blockadedText.setPosition(pos2di((topWidth - 238) / 2 , 2));
		structuresText.setPosition(pos2di(topWidth - 358, 2));
		nextButton.setPosition(pos2di(topWidth - 107, 1));
		prevButton.setPosition(pos2di(topWidth - 207, 1));

		governor.setPosition(pos2di(topWidth - 197 + 7, 41 + 19));
		useGovernor.setPosition(pos2di(topWidth - 197, 63));

		// Position resource grid
		resources.setCellSize(dim2di((size.width - 14) / 6, 17));

		// Position tabs
		int tabSize = (size.width - 14 - 2*4) / 3;

		queueTab.setPosition(pos2di(0, 127));
		structsTab.setPosition(pos2di(4 + tabSize, 127));
		econTab.setPosition(pos2di(8 + tabSize*2, 127));
		
		queueTab.setSize(dim2di(tabSize, 18));
		structsTab.setSize(dim2di(tabSize, 18));
		econTab.setSize(dim2di(tabSize, 18));

		// Position tab contents
		recti contentRect = recti(pos2di(6, 168), size - dim2di(12, 175));
		pos2di topLeft = contentRect.UpperLeftCorner;
		size = contentRect.getSize();

		// * Queue Tab
		queuePanel.setPosition(topLeft);
		queuePanel.setSize(size);

		queueEle.setPosition(pos2di(213, 62));
		queueEle.setSize(dim2di(size.width - 213 - 180, size.height - 60));
		planet_queue.syncPosition(queueEle);

		hb_panel.setPosition(queueEle.getPosition());
		hb_panel.setSize(queueEle.getSize());
		hovered_build_panel.setSize(hb_panel.getSize() - dim2di(10, 6));

		hovered_cost.setPosition(pos2di(10, queueEle.getSize().height - 22));
		hovered_cost.setCellSize(dim2di(queueEle.getSize().width / 4, 17));

		queueName.setPosition(pos2di(219, 4));
		queueName.setSize(dim2di(size.width - 219 - 206, 18));

		buildShipsList.setSize(dim2di(209, size.height - 47));
		buildStructsList.setSize(dim2di(209, size.height - 23));

		shipSort.setSize(dim2di(208, 18));
		shipSort.setPosition(pos2di(1, size.height - 18));

		activeCost.setPosition(pos2di(size.width - 232, 10));
		totalCost.setPosition(pos2di(size.width - 168, 96));
		totalText.setPosition(pos2di(size.width - 173, 64));

		// Queue actions
		clearQueueButton.setPosition(pos2di(size.width - 174, size.height - 22));
		saveQueueButton.setPosition(pos2di(size.width - 174, size.height - 44));
		loadQueueButton.setPosition(pos2di(size.width - 174, size.height - 66));

		pauseButton.setPosition(pos2di(size.width - 174, size.height - 94));
		repeatButton.setPosition(pos2di(size.width - 87, size.height - 94));

		// * Structures tab
		structsPanel.setPosition(topLeft);
		structsPanel.setSize(size);

		structsList.setSize(dim2di(259, size.height - 26));
		renovateStructButton.setPosition(pos2di(1, size.height - 22));
		removeStructButton.setPosition(pos2di(131, size.height - 22));
		structureInfo.setSize(dim2di(size.width - 275, size.height - 9));

		// * Economy tab
		econPanel.setPosition(topLeft);
		econPanel.setSize(size);
	}

	void draw(GuiElement@ ele) {
		ele.toGuiScripted().setAbsoluteClip();
		const recti absPos = ele.getAbsolutePosition();
		pos2di topLeft = absPos.UpperLeftCorner;
		pos2di botRight = absPos.LowerRightCorner;
		dim2di size = absPos.getSize();

		// Draw top area
		drawWindowFrame(absPos);
		drawResizeHandle(recti(botRight - pos2di(19, 19), botRight));

		drawHSep(recti(topLeft + pos2di(6, 113), dim2di(size.width-12, 7)));
		drawDarkArea(recti(topLeft + pos2di(7, 119), pos2di(botRight.x - 7, topLeft.y + 141)));

		drawRect(recti(topLeft + pos2di(7, 20), topLeft + pos2di(117, 114)), Color(0xff000000));
		drawVSep(recti(topLeft + pos2di(116, 19), dim2di(7, 96)));

		drawDarkArea(recti(topLeft + pos2di(123, 20), pos2di(botRight.x - 7, topLeft.y + 41)));
		drawHSep(recti(topLeft + pos2di(122, 40), dim2di(size.width-128, 7)));
		drawVSepSmall(recti(pos2di(botRight.x - 213, topLeft.y + 19), dim2di(6, 23)));

		drawDarkArea(recti(topLeft + pos2di(123, 47), pos2di(botRight.x - 7, topLeft.y + 114)));
		drawVSepSmall(recti(pos2di(botRight.x - 213, topLeft.y + 46), dim2di(6, 69)));

		drawTabBar(recti(topLeft + pos2di(6, 140), dim2di(size.width-12, 29)));

		// Draw queue tab
		if (queuePanel.isVisible()) {
			// Left separator
			drawVSep(recti(topLeft + pos2di(214, 168), dim2di(7, size.height - 174)));
			drawHSep(recti(pos2di(topLeft.x + 6, topLeft.y + 186), dim2di(210, 7)));

			if (buildShipsList.isVisible())
				drawHSep(recti(pos2di(topLeft.x + 6, botRight.y - 32), dim2di(210, 7)));

			// Top Right separators
			drawHSep(recti(topLeft + pos2di(220, 224), dim2di(size.width - 226, 7)));
			drawVSepSmall(recti(pos2di(botRight.x - 252, topLeft.y + 168), dim2di(6, 58)));
			drawHSep(recti(topLeft + pos2di(220, 190), dim2di(size.width - 220 - 251, 7)));

			// Right separators
			drawVSep(recti(pos2di(botRight.x - 187, topLeft.y + 230), dim2di(7, size.height - 236)));
			drawHSep(recti(pos2di(botRight.x - 181, botRight.y - 80), dim2di(175, 7)));
			drawHSep(recti(pos2di(botRight.x - 181, botRight.y - 108), dim2di(175, 7)));
			drawHSep(recti(pos2di(botRight.x - 181, topLeft.y + 252), dim2di(175, 7)));

			// Queue resource area
			drawDarkArea(recti(pos2di(botRight.x - 247, topLeft.y + 169), pos2di(botRight.x - 7, topLeft.y + 225)));

			// Total cost title
			drawDarkArea(recti(pos2di(botRight.x - 181, topLeft.y + 231), pos2di(botRight.x - 7, topLeft.y + 253)));

			// Total cost area
			drawDarkArea(recti(pos2di(botRight.x - 181, topLeft.y + 259), pos2di(botRight.x - 7, botRight.y - 107)));

			// Queue area
			drawLightArea(recti(topLeft + pos2di(221, 231), botRight - pos2di(186, 7)));

			// Construction name area
			drawDarkArea(recti(topLeft + pos2di(221, 169), pos2di(botRight.x - 251, topLeft.y + 191)));

			// Repeat queue
			if (repeat)
				drawSprite("res_repeat", 1, pos2di(botRight.x - 268, topLeft.y + 172));

			// Progress bar
			recti progressArea(topLeft + pos2di(221, 197),
					pos2di(botRight.x - 251, topLeft.y + 197 + 28));

			drawDarkArea(progressArea);

			int newWidth = floor((progressArea.getSize().width - 4) / 12) * 12 + 4;
			progressArea = recti(progressArea.UpperLeftCorner + pos2di((progressArea.getSize().width - newWidth) / 2, 0),
								dim2di(newWidth, 28));

			drawProgressBar(progressArea, max(progress, 0.f), progress >= 0 ? Color(0xffffffff) : Color(0xaaffffff));
		}
		else if (structsPanel.isVisible()) {
			drawVSep(recti(topLeft + pos2di(264, 168), dim2di(7, size.height - 174)));
			drawHSep(recti(pos2di(topLeft.x + 6, botRight.y - 35), dim2di(260, 7)));
			drawLightArea(recti(topLeft + pos2di(271, 169), botRight - pos2di(7, 7)));
		}
		else if (econPanel.isVisible()) {
			drawLightArea(recti(topLeft + pos2di(7, 169), pos2di(botRight.x - 7, topLeft.y + 82 + 169)));
			drawHSep(recti(topLeft + pos2di(6, 81 + 169), dim2di(size.width - 12, 7)));
			drawDarkArea(recti(topLeft + pos2di(7, 88 + 169), dim2di(size.width - 14, 22)));
			drawHSep(recti(topLeft + pos2di(6, 109 + 169), dim2di(size.width - 12, 7)));
			drawLightArea(recti(topLeft + pos2di(7, 116 + 169), botRight - pos2di(7, 7)));
		}

		clearDrawClip();
	}

	void update(float time) {
		Empire@ emp = getActiveEmpire();

		// * Check if we should switch planets
		if (!pinned) {
			Object@ selObj = getSelectedObject(getSubSelection());
			Planet@ selPl = selObj;

			if (selPl !is null && selObj.getOwner() is emp)
				setPlanet(selPl);
		}

		// Further information can only be accessed for owned planets
		Planet@ pl = planet;
		Object@ obj = planet;

		if (obj is null || obj.getOwner() !is getActiveEmpire())
			return;

		// * Update interface
		if (governor.getItemCount() != emp.getBuildListCount())
			updateGovernorList();

		// * Update all information
		// Update top bar information
		updateCurrentGovernor();
		useGovernor.setChecked(planet.usesGovernor());
		updateBuildables();

		float[] tmode(4);
		bool hasImport = true;
		bool hasExport = true;
		if (obj.getStateVals(strTradeMode, tmode[0], tmode[1], tmode[2], tmode[3])) {
			for (uint i = 0; i < 4; ++i) {
				int mode = int(tmode[i]);
				if (mode == 1 || mode == 3) {
					hasExport = false;
				}
				if (mode == 2 || mode == 3) {
					hasImport = false;
				}
			}
		}

		allowImport.setChecked(hasImport);
		allowExport.setChecked(hasExport);

		// Update blockaded
		System@ parent = obj.getParent();
		blockaded = parent !is null && parent.isBlockadedFor(emp);

		blockadedText.setVisible(blockaded);

		// Update planet condition listing if necessary
		if (planet.getConditionCount() != conditions.length())
			updateConditions();

		// Count amount of structures
		PlanetStructureList structs;
		structs.prepare(planet);

		int strCnt = structs.getCount();
		structuresText.setText(combine(i_to_s(strCnt), "/", f_to_s(planet.getMaxStructureCount(), 0), " ", localize("#slots")));
		refreshCurStructs();

		// Update resources
		ObjectLock lock(obj);
		float val = 0.f, max = 0.f, cargo = 0.f, req = 0.f;

		// - Food levels
		if (obj.getStateVals(strFood, val, max, req, cargo))
			resources.update(0, val + cargo, max);

		// - Deep Ore levels
		if (obj.getStateVals(strDeep, val, max, req, cargo))
			resources.update(1, val);

		// - Damage levels
		if (obj.getStateVals(strDamage, val, max, req, cargo))
			resources.update(2, max - val);

		// - Labor levels
		if (obj.getStateVals(strLabor, val, max, req, cargo))
			resources.update(3, val, max);

		// - Worker levels
		if (obj.getStateVals(strWorkers, val, max, req, cargo))
			resources.update(4, val - req, val);

		// - Mood levels
		if (obj.getStateVals(strMood, val, max, req, cargo))
			resources.update(5, val, 1);

		// Update planet queue
		uint queueSize = obj.getConstructionQueueSize();
		if (queueSize != lastQueueSize || queueSize > 0) {
			planet_queue.syncToQueue(pl);

			if (queueSize > 0) {
				progress = obj.getConstructionProgress(0);
				queueName.setText(combine(obj.getConstructionName(0), " (", f_to_s(progress * 100.f, 0), "%)"));

				float req = 0.f, done = 0.f;
				obj.getConstructionCost(0, strMetl, done, req);
				activeCost.update(1, done, req);

				obj.getConstructionCost(0, strElec, done, req);
				activeCost.update(2, done, req);

				obj.getConstructionCost(0, strAdvp, done, req);
				activeCost.update(0, done, req);
				
				obj.getConstructionCost(0, strLabor, done, req);
				activeCost.update(3, done, req);
			}
			else {
				progress = -1.f;
				queueName.setText(localize("#PL_NOTHING"));

				activeCost.update(0, "---");
				activeCost.update(1, "---");
				activeCost.update(2, "---");
				activeCost.update(3, "---");
			}
		}

		// Check for repeat or pause queue
		repeat = obj.getRepeatQueue();
		pause = obj.getPauseQueue();

		repeatButton.setPressed(repeat);
		pauseButton.setPressed(pause);

		// Full queue check timer
		queueCheckTime -= time;
		if (queueCheckTime < 0 || queueSize != lastQueueSize) {
			queueCheckTime = queueCheckDelay;

			float totalMtl = 0.f, totalElc = 0.f, totalAdv = 0.f, totalLabr = 0.f;
			buildingStructures = 0;

			uint cnt = obj.getConstructionQueueSize();
			for (uint i = 0; i < cnt; ++i) {
				string@ type = obj.getConstructionType(i);
				if (@type != null && type == "structure")
					++buildingStructures;
			
				if(queuePanel.isVisible()) {
					float req, done;

					obj.getConstructionCost(i, "Metals", done, req);
					totalMtl += req;

					obj.getConstructionCost(i, "Electronics", done, req);
					totalElc += req;

					obj.getConstructionCost(i, "AdvParts", done, req);
					totalAdv += req;
					
					obj.getConstructionCost(i, "Labr", done, req);
					totalLabr += req;
				}
			}

			if (queuePanel.isVisible()) {
				totalCost.update(0, totalAdv);
				totalCost.update(1, totalMtl);
				totalCost.update(2, totalElc);
				totalCost.update(3, totalLabr);
			}

			Color col;
			if (planet.getMaxStructureCount()-planet.getStructureCount()-buildingStructures > 0) {
				col = Color(255, 255, 255, 255);
				canBuildStructures = true;
			} else {
				col = Color(255, 160, 160, 160);
				canBuildStructures = false;
			}

			uint it_cnt = buildStructsList.getItemCount();
			for (uint i = 0; i < it_cnt; ++i)
				buildStructsList.setItemOverrideColor(i, col);
		}

		lastQueueSize = queueSize;

		// Update economy
		if (econPanel.isVisible()) {
			if (econUpdateTick < 0) {
				updateEconText(true);
				econUpdateTick = econUpdateLength;
			}
			else {
				econUpdateTick -= time;
				updateEconText(false);
			}
		}
	
		// Request object syncs periodically
		if(isClient()) {
			syncTimer -= time;
			if(syncTimer < 0) {
				syncTimer = syncDelay;
				requestObjectSync(obj);
			}
		}
	}

	void onPlanetChange(Planet@ pl) {
		Object@ obj = pl;
		if (obj is null)
			return;

		// Update static planet data
		name.setColor(obj.getOwner().color);
		name.setText(obj.getName());

		int ind = getPlanetIconIndex(pl.getPhysicalType());
		planetIco.setSprites("planet_icons", ind, ind, ind);

		pinImg.setPosition(pos2di(name.getPosition().x + getTextDimension(name.getText(), "stroked_subtitle").width + 7, 7));

		// Further information can only be accessed for owned planets
		if (obj.getOwner() !is getActiveEmpire())
			return;

		updateConditions();
		refreshCurStructs();
		resetRates();
	}

	void updateConditions() {
		// Remove old conditions
		for (uint i = 0; i < conditions.length(); ++i) {
			conditions[i].remove();
			@conditions[i] = null;
		}

		// Add new conditions
		uint condCnt = planet.getConditionCount();
		conditions.resize(condCnt);
		noConditionText.setVisible(condCnt == 0);

		for (uint i = 0; i < condCnt; ++i) {
			const PlanetCondition@ cond = planet.getCondition(i);
			@conditions[i] = GuiExtText(recti(pos2di(125+(floor(i/2)*180), 40+24*(i%2)),
						dim2di(150, 20)), topPanel);
			conditions[i].setText(localize("#PC_"+cond.get_id()));
			conditions[i].setToolTip(cond.desc);
		}
	}

	void updateGovernorList() {
		Empire@ emp = getActiveEmpire();

		governor.clear();
		int cnt = emp.getBuildListCount();
		for (int i = 0; i < cnt; ++i)
			governor.addItem(localize("#PG_" + emp.getBuildList(i)));
	}

	void updateCurrentGovernor() {
		string@ curGov = planet.getGovernorType();
		Empire@ emp = getActiveEmpire();

		uint item = governor.getSelected();
		string@ prevGov = emp.getBuildList(item);

		if (curGov != prevGov) {
			int num = governor.getItemCount();

			for (int i = 0; i < num; i++) {
				if (emp.getBuildList(i) == curGov) {
					governor.setSelected(i);
					break;
				}
			}
		}
	}

	void updateBuildables() {	
		const Empire@ emp = getActiveEmpire();
		uint sysCount = emp.getSubSysDataCnt();
		if(lastBuildables != sysCount) {
			lastBuildables = sysCount;
			buildIDs.resize(sysCount);
			buildStructsList.clear();
			uint j = 0;
			for(uint i = 0; i < sysCount; ++i) {
				const subSystemDef@ def = emp.getSubSysData(i).type;
				if(def.canBuildOn(planet.toObject())) {
					buildStructsList.addItem(def.getName());
					buildIDs[j] = i;
					++j;
				}
			}
		}
		
		// Figure out the sort mode
		int sel = shipSort.getSelected();
		bool updateNow = false;
		if (sel != -1) {
			int mode = (sel % 3) - 1;
			if (mode < 0)
				mode = 0;

			updateNow = layouts.setSortMode(BlueprintSortMode(mode), sel < 3);
		}

		// Update layouts
		if(layouts.update(emp, updateNow))
			layouts.fill(buildShipsList);
	}

	EventReturn onMouseEvent(GuiElement@ ele, const MouseEvent& evt) {
		DragResizeEvent re = handleDragResize(ele, evt, drag, MIN_WIDTH, MIN_HEIGHT);
		if (re != RE_None) {
			if (re == RE_Resized)
				syncPosition(ele.getSize());
			return ER_Absorb;
		}
		return ER_Pass;
	}

	void switchTab(int num) {
		queueTab.setPressed(num == 0);
		structsTab.setPressed(num == 1);
		econTab.setPressed(num == 2);

		queuePanel.setVisible(num == 0);
		structsPanel.setVisible(num == 1);
		econPanel.setVisible(num == 2);

		if (num == 2) {
			resetRates();
			updateEconText(true);
		}
	}

	EventReturn onGUIEvent(GuiElement@ ele, const GUIEvent& evt) {
		if (evt.EventType == GEVT_Focus_Gained && evt.Caller.isAncestor(ele)) {
			ele.bringToFront();
			bindEscapeEvent(ele);
		}

		switch (evt.EventType) {
			case GEVT_Closed:
				closePlanetWindow(this);
				return ER_Absorb;
			case GEVT_Clicked:
				if (evt.Caller is close) {
					closePlanetWindow(this);
					return ER_Absorb;
				}
				else if (evt.Caller is queueTab) {
					switchTab(0);
					return ER_Pass;
				}
				else if (evt.Caller is structsTab) {
					switchTab(1);
					return ER_Pass;
				}
				else if (evt.Caller is econTab) {
					switchTab(2);
					return ER_Pass;
				}
				else if (evt.Caller is nextButton) {
					nextPlanet();
					return ER_Pass;
				}
				else if (evt.Caller is prevButton) {
					prevPlanet();
					return ER_Pass;
				}
				else if (evt.Caller is planetIco) {
					selectObject(planet.toObject());
					return ER_Pass;
				}
				else if (evt.Caller is zoomButton) {
					setCameraFocus(planet.toObject());
					setGuiFocus(null);
					return ER_Pass;
				}
				else if (queuePanel.isVisible()) {
					if (evt.Caller is pauseButton) {
						setPause(!planet.toObject().getPauseQueue());
						return ER_Pass;
					}
					else if (evt.Caller is repeatButton) {
						setRepeat(!planet.toObject().getRepeatQueue());
						return ER_Pass;
					}
					else if (evt.Caller is clearQueueButton) {
						planet.toObject().clearBuildQueue();
						return ER_Pass;
					}
					else if (evt.Caller is saveQueueButton) {
						savePlanetQueue(planet.toObject());
						return ER_Pass;
					}
					else if (evt.Caller is loadQueueButton) {
						loadPlanetQueue(planet.toObject());
						return ER_Pass;
					}
					else if (evt.Caller is buildShipsTab) {
						buildShipsTab.setPressed(true);
						buildStructsTab.setPressed(false);

						buildShipsList.setVisible(true);
						shipSort.setVisible(true);
						buildStructsList.setVisible(false);
						setGuiFocus(buildShipsList);
						return ER_Pass;
					}
					else if (evt.Caller is buildStructsTab) {
						buildShipsTab.setPressed(false);
						buildStructsTab.setPressed(true);

						buildShipsList.setVisible(false);
						shipSort.setVisible(false);
						buildStructsList.setVisible(true);
						setGuiFocus(buildStructsList);
						return ER_Pass;
					}
				}
				else if (structsPanel.isVisible()) {
					if (evt.Caller is renovateStructButton) {
						renovateStructure();
						return ER_Pass;
					}
					else if (evt.Caller is removeStructButton) {
						removeStructure();
						return ER_Pass;
					}
				}
			break;
			case GEVT_Mouse_Over:
				if (evt.Caller is hb_panel) {
					hideHoverInfo();
					return ER_Pass;
				}
			break;
			case GEVT_Listbox_Selected_Again:
				if (evt.Caller is buildStructsList) {
					buildStructure();
					return ER_Pass;
				}
				else if (evt.Caller is buildShipsList) {
					buildShip();
					return ER_Pass;
				}
			break;
			case GEVT_Listbox_Hovered:
				if (evt.Caller is buildStructsList) {
					hoverStructure();
					return ER_Pass;
				}
				else if (evt.Caller is buildShipsList) {
					hoverShip();
					return ER_Pass;
				}
			break;
			case GEVT_Listbox_Changed:
				if (evt.Caller is structsList) {
					refreshStructInformation();
					return ER_Pass;
				}
			break;
			case GEVT_Mouse_Left:
				if (evt.Caller is buildStructsList) {
					hideHoverInfo();
					return ER_Pass;
				}
				else if (evt.Caller is buildShipsList) {
					hideHoverInfo();
					return ER_Pass;
				}
			break;
			case GEVT_Right_Clicked:
				if (evt.Caller is planetIco) {
					Object@ obj = planet.toObject();
					triggerContextMenu(obj);
					return ER_Pass;
				}
			break;
			case GEVT_ComboBox_Changed:
				if (evt.Caller is governor) {
					setGovernor(governor.getSelected());
				}
			break;
			case GEVT_Checkbox_Toggled:
				if (evt.Caller is useGovernor) {
					setUseGovernor(useGovernor.isChecked());
					return ER_Pass;
				}
				else if (evt.Caller is allowImport || evt.Caller is allowExport) {
					int mode = 0;
					if (!allowImport.isChecked()) {
						if (!allowExport.isChecked())
							mode = 3;
						else
							mode = 2;
					}
					else if (!allowExport.isChecked()) {
						mode = 1;
					}

					setTradeMode(mode);
				}
			break;
			case GEVT_Focus_Gained:
				if (evt.Caller is pinImg) {
					setPinned(!isPinned());
					return ER_Absorb;
				}
				else if (evt.Caller is governor) {
					governor.bringToFront();
					return ER_Pass;
				}
			break;
		}

		return ER_Pass;
	}

	EventReturn onKeyEvent(GuiElement@ ele, const KeyEvent& evt) {
		if (evt.pressed) {
			if (evt.key == 221) {
				nextPlanet();
				return ER_Absorb;
			}
			if (evt.key == 219) {
				prevPlanet();
				return ER_Absorb;
			}
		}
		return ER_Pass;
	}

	/* }}} */
	/* {{{ Structure list */
	const subSystemDef@ getRealSelectedStructure(int& level) {
		//Get the subsystem description for the selected item in the structure list
		uint i = structsList.getSelected();
		string@ name = structsList.getItem(i);
		uint num = name.find("x");
		uint ID, Level;

		name = name.substr(num+2, name.length()-num-2);
		structures.get(name, ID);
		levels.get(name, Level);

		level = int(Level);
		const subSystemDef@ def = getSubSystemDefByID(ID);
		return def;
	}

	int getStructureByDef(PlanetStructureList& list, const subSystemDef@ def, int index, int level) {
		//Get the structure index of the nth structure matching def
		int cnt = list.getCount();
		int j = 0;
		int ret = 0;

		for (int i = 0; i < cnt; ++i) {
			const subSystem@ subs = list.getStructure(i);
			if (subs.type.ID == def.ID && (level == 0 || round(subs.level) == level)) {
				if (index == -1)
					ret = i;
				else if (j == index)
					return i;
				else
					++j;
			}
		}

		return ret;
	}

	void renovateStructure() {
		PlanetStructureList list;
		list.prepare(planet);

		if(shiftKey) {
			int structIndex = planet.getStructureCount();
			for(int i = 0; i < structIndex; ++i)
				planet.rebuildStructure(i);
		}
		else {
			int itemSelected = structsList.getSelected();
			if(itemSelected >= 0)
				renovateSelectedStructures(list);
		}
	}

	void renovateSelectedStructures(PlanetStructureList& list) {
		int level = 0;
		const subSystemDef@ def = getRealSelectedStructure(level);
		uint cnt = list.getCount();

		for (uint i = 0; i < cnt; ++i) {
			const subSystem@ subs = list.getStructure(i);
			if (subs.type.ID == def.ID && level == round(subs.level)) {
				planet.rebuildStructure(i);
			}
		}
	}

	void removeStructure() {
		int itemSelected = structsList.getSelected();
		if(itemSelected >= 0 && uint(itemSelected) < planet.getStructureCount()) {
			PlanetStructureList list;
			list.prepare(planet);

			int level = 0, remove = -1;
			const subSystemDef@ def = getRealSelectedStructure(level);
			uint cnt = list.getCount();

			for (uint i = 0; i < cnt; ++i) {
				const subSystem@ subs = list.getStructure(i);
				if (subs.type.ID == def.ID && level == round(subs.level)) {
					if (shiftKey) {
						planet.removeStructure(i);
						--i; --cnt;
					}
					else
						remove = i;
				}
			}

			if (!shiftKey && remove >= 0)
				planet.removeStructure(remove);
		}
	}

	void refreshStructInformation() {
		int itemSelected = structsList.getSelected();
		if(itemSelected >= 0) {
			PlanetStructureList list;
			list.prepare(planet);

			int level = 0;
			const subSystemDef@ def = getRealSelectedStructure(level);
			uint num = getStructureByDef(list, def, -1, level);
			const subSystem@ subsys = @list.getStructure(num);

			string@ text = "#font:frank_12#"+def.getName();
			text += ": ("+localize("#PH_Level")+" " + f_to_s(subsys.level,0) + ")#font#\n";
			text += def.getDescription()+"\n";
			uint hintCount = def.getHintCount();
			for(uint i = 0; i < hintCount; ++i) {
				float val = subsys.getHint(i);
				string@ hintName = def.getHintName(i);
				text += ("#c#\n#tab:6#" + localize("#PH_" + hintName)) + ": ";
				if(val >= 0)
					text += "#c:green#" + standardize(val) + "#c#";
				else
					text += "#c:red#" + standardize(val) + "#c#";
			}
			structureInfo.setText(text);
		}
	}

	void refreshCurStructs() {
		if(planet is null)
			return;
		
		PlanetStructureList list;
		list.prepare(planet);

		uint strCnt = list.getCount();
		int selected = structsList.getSelected();

		string@ offline = localize("#PL_OFFLINE");
		string@ destroyed = localize("#PL_DESTROYED");
		UniqueList@ ulist = UniqueList(strCnt);
		
		for(uint i = 0; i < strCnt; ++i) {
			const subSystem@ sys = list.getStructure(i);
			string@ sysName = sys.type.getName();
			if(!sys.type.hasTag(strUnique))
				sysName += " " + f_to_s(sys.level, 0);
			switch(list.getStructureState(i).getState()) {
				case SS_Disabled:
					sysName += " - "+offline;
					break;
				case SS_Destroyed:
					sysName += " - "+destroyed;
					break;
			}

			ulist.add(sysName);

			// Store subsystem ID for further use
			structures.set(sysName, sys.type.ID);
			levels.set(sysName, round(sys.level));
		}

		bool clearList = ulist.size() != prevStructGroups;
		if(clearList)
			structsList.clear();
		prevStructGroups = ulist.size();

		for (uint i = 0; i < prevStructGroups; ++i) {
			string@ sysName = ulist.getAmount(i)+"x "+ulist.getName(i);

			if(clearList)
				structsList.addItem(sysName);
			else
				structsList.setItem(i, sysName);
		}

		if(clearList)
			structsList.setSelected(selected < int(strCnt) ? selected : -1);

		if (structsList.getSelected() == -1 && structsList.getItemCount() > 0) {
			structsList.setSelected(0);
			refreshStructInformation();
		}
	}
	/* }}} */
	/* {{{ Economy values */
	float advAvg;
	float elcAvg;
	float mtlAvg;
	float tradeAvg;
	float fulAvg;
	float amoAvg;

	float advExpAvg;
	float elcExpAvg;
	float mtlExpAvg;
	float fudExpAvg;
	float luxExpAvg;
	float gudExpAvg;
	float fulExpAvg;
	float amoExpAvg;

	void resetRates() {
		advAvg = -1.f;
		elcAvg = -1.f;
		mtlAvg = -1.f;
		tradeAvg = -1.f;
		fulAvg = -1.f;
		amoAvg = -1.f;
		
		
		advExpAvg = -1.f;
		elcExpAvg = -1.f;
		mtlExpAvg = -1.f;
		fudExpAvg = -1.f;
		luxExpAvg = -1.f;
		gudExpAvg = -1.f;
		fulExpAvg = -1.f;
		amoExpAvg = -1.f;
	}

	void updateRate(GuiStaticText@ ele, float val) {
		float absRate = abs(val);

		if (absRate < 0.01f) {
			ele.setColor(Color(0xffb4b4b4));
			ele.setText("0.00");
		}
		else if (val < 0) {
			ele.setColor(Color(0xffff0000));
			ele.setText("-"+standardize_nice(absRate));
		}
		else {
			ele.setColor(Color(0xff00ff00));
			ele.setText("+"+standardize_nice(absRate));
		}
	}

	void updateExport(GuiStaticText@ ele, float val) {
		float absRate = abs(val);

		if (absRate < 0.01f) {
			ele.setColor(Color(0xffb4b4b4));
			ele.setText("0.00");
		}
		else if (val < 0) {
			ele.setColor(Color(0xff00afff));
			ele.setText("-"+standardize_nice(absRate));
		}
		else {
			ele.setColor(Color(0xffff7f00));
			ele.setText("+"+standardize_nice(absRate));
		}
	}

	void updateStorage(uint index, float stored, float max) {
		Color col(0xffffffff);
		col = col.interpolate(Color(0xffd48a3a), clamp(stored/max, 0.f, 1.f));

		economyValues[(index*7)+1].setColor(col);

		economyValues[(index*7)+1].setText(standardize_nice(stored));
		economyValues[(index*7)+2].setText(standardize_nice(max));
	}

	void updateRate(uint index, float inc, float exp, float traded) {
		updateRate(economyValues[(index*7)+3], inc);
		updateRate(economyValues[(index*7)+4], exp);
		updateExport(economyValues[(index*7)+5], traded);

		// Ignore net rates smaller than a thousandth of anything
		float net = inc+exp+traded;
		if (net < inc/1000.f || net < exp/1000.f || net < traded/1000.f)
			net = 0;
		updateRate(economyValues[(index*7)+6], net);
	}

	float movingAvg(float val, float avg) {
		if (avg < -0.5f)
			return val;
		return 0.9f * avg + 0.1f * val;
	}

	string@ standardize_nice(float val) {
		if (val > 0.0001f)
			return standardize(val);
		else
			return "0.00";
	}

	void updateEconText(bool updateText) {
		// Get raw data
		Object@ obj = planet;
		Empire@ emp = obj.getOwner();
		float mood = 0.f, temp = 0.f, pop = 0.f;

		obj.getStateVals(strWorkers, pop, temp, temp, temp);
		obj.getStateVals(strMood, mood, temp, temp, temp);

		double population = double(pop);

		// Get base multipliers
		float popMult = float(0.5 * (0.5 + (population / (60.0 * million))));
		float moodMult = pow(2, mood);

		float val = 0.f, required = 0.f;
		obj.getStateVals(strWorkers, val, temp, required, temp);
		float workersMult = clamp(val / max(required,1.f),0.f,1.f);

		float gudsCons = float(population * (15.0 / million));
		float luxsCons = float(population * (1.5 / million));

		bool hasCivilActs = !emp.hasTraitTag(strDisableCivilActs);
		bool hasMood = !emp.hasTraitTag(strIndifferent);

		if (hasCivilActs) {
			if(emp.getSetting(actShortWorkWeek) == 1)
				popMult *= 0.75;
			else if(emp.getSetting(actForcedLabor) == 1)
				popMult *= 0.8f;

			if (emp.getSetting(actTaxBreak) == 1) {
				gudsCons *= 1.5f;
				luxsCons *= 1.5f;
			}
		}

		if (hasMood) {
			if (emp.hasTraitTag(strLowLuxuries))
				luxsCons *= 0.5f;
			else if (emp.hasTraitTag(strHighLuxuries))
				luxsCons *= 2.f;
		}

		float tradeRequired = 0.f, tradeMax = 0.f;
		obj.getStateVals(strTrade, temp, tradeMax, tradeRequired, temp);
		tradeAvg = movingAvg(tradeRequired, tradeAvg);

		if (updateText) {
			econ_popmult.setText(ftos_nice(popMult, 1)+"x");
			econ_moodmult.setText(f_to_s(moodMult*100, 0)+"%");
			econ_workersmult.setText(f_to_s(workersMult*100, 0)+"%");

			econ_pop.setText(standardize(float(population)));

			string@ tradeText = combine(standardize_nice(tradeAvg), "/", standardize_nice(tradeMax));
			if (blockaded) {
				econ_trade.setText(combine(tradeText, " - ", localize("#MO_Blockade")));
				econ_trade.setToolTip(localize("#MOTT_Blockade"));
				econ_trade.setColor(Color(0xffff0000));
			}
			else {
				econ_trade.setText(tradeText);
				econ_trade.setColor(Color(0xffffffff));
				econ_trade.setToolTip(null);
			}
		}

		// Get resource consumptions
		float advGen = 0.f, elcGen = 0.f, mtlGen = 0.f, foodGen = 0.f, luxsGen = 0.f, gudsGen = 0.f;
		float advTrans = 0.f, elcTrans = 0.f, mtlTrans = 0.f, fudTrans = 0.f;
		float mtlCons = 0.f, elcCons = 0.f, foodCons = 0.f;
		float gotGuds = 0.f, gotLuxs = 0.f;
		float fulGen = 0.f, amoGen = 0.f, fulTrans = 0.f, amoTrans = 0.f;

		obj.getStateVals(strAdvpGen, advGen,  temp, temp, advTrans);
		obj.getStateVals(strElecGen, elcGen,  temp, temp, elcTrans);
		obj.getStateVals(strMetlGen, mtlGen,  temp, temp, mtlTrans);
		
		obj.getStateVals(strFoodGen, foodGen, temp, temp, fudTrans);
		obj.getStateVals(strFuelGen, fulGen,  temp, temp, fulTrans);
		obj.getStateVals(strAmmoGen, amoGen,  temp, temp, amoTrans);
		obj.getStateVals(strGudsGen, gudsGen, temp, temp, gotGuds);
		obj.getStateVals(strLuxsGen, luxsGen, temp, temp, gotLuxs);

		advAvg = movingAvg(advGen, advAvg);
		mtlAvg = movingAvg(mtlGen, mtlAvg);
		elcAvg = movingAvg(elcGen, elcAvg);
		fulAvg = movingAvg(fulGen, fulAvg);
		amoAvg = movingAvg(amoGen, amoAvg);

		advExpAvg = movingAvg(advTrans, advExpAvg);
		mtlExpAvg = movingAvg(mtlTrans, mtlExpAvg);
		elcExpAvg = movingAvg(elcTrans, elcExpAvg);
		fudExpAvg = movingAvg(fudTrans, fudExpAvg);
		gudExpAvg = movingAvg(gotGuds, gudExpAvg);
		luxExpAvg = movingAvg(gotLuxs, luxExpAvg);
		fulExpAvg = movingAvg(fulTrans, fulExpAvg);
		amoExpAvg = movingAvg(amoTrans, amoExpAvg);

		foodCons = float(population * (0.06 / million));
		mtlCons = advGen + elcGen * 2.f;
		elcCons = advGen;

		if (emp.hasTraitTag(strNoFood))
			foodCons = 0.f;
		else if (emp.hasTraitTag(strFastConsumption))
			foodCons *= 2.f;

		if (updateText) {
			const subSystemDef@ def = getSubSystemDefByName("GalacticCapital");

			if (planet.getStructureCount(def) > 0) {
				advGen = gc_adv;
				elcGen = gc_elc;
				foodGen += gc_fud;
				mtlGen = gc_mtl;
			}
			else {
				advGen = 0.f;
				elcGen = 0.f;
				mtlGen = 0.f;
			}

			float val = 0.f, max = 0.f, cargo = 0.f, temp = 0.f;
			if (obj.getStateVals( strAdvp, val, max, temp, cargo))		updateStorage(0, val+cargo, max);
			if (obj.getStateVals( strElec, val, max, temp, cargo))		updateStorage(1, val+cargo, max);
			if (obj.getStateVals( strMetl, val, max, temp, cargo))		updateStorage(2, val+cargo, max);
			if (obj.getStateVals( strFood, val, max, temp, cargo))		updateStorage(3, val+cargo, max);
			
			if (obj.getStateVals( strFuel, val, max, temp, cargo))		updateStorage(6, val+cargo, max);
			if (obj.getStateVals( strAmmo, val, max, temp, cargo))		updateStorage(7, val+cargo, max);		

			updateRate(0, advAvg+advGen, 0,         -advExpAvg);
			updateRate(1, elcAvg+elcGen, -elcCons,  -elcExpAvg);
			updateRate(2, mtlAvg+mtlGen, -mtlCons,  -mtlExpAvg);
			updateRate(3, foodGen,       -foodCons, -fudExpAvg);

			if (hasMood) {
				updateRate(4, gudsGen, -gudsCons, gudExpAvg);
				updateRate(5, luxsGen, -luxsCons, luxExpAvg);
			}
			else {
				updateRate(4, 0, 0, 0);
				updateRate(5, 0, 0, 0);
			}
			
			updateRate(6, fulAvg+fulGen, 0,         -fulExpAvg);
			updateRate(7, amoAvg+amoGen, 0,         -amoExpAvg);
		}
	}
	/* }}} */
	/* {{{ Constructible hover information */
	void hoverStructure() {
		hb_panel.setVisible(true);

		int itemHovered = buildStructsList.getHovered();
		if(itemHovered >= 0 && uint(itemHovered) < buildStructsList.getItemCount()) {
			const subSystemDef@ def = planet.toObject().getOwner().getSubSysData(buildIDs[itemHovered]).type;
			
			SubSystemFactory factory;
			factory.objectScale = 10.f;
			factory.objectSizeFactor = 10.f;
			factory.prepare(planet);
			if(factory.generateSubSystems(def, null)) {
				subSystem@ subsys = factory.get_active();
				
				string@ text = "#font:frank_12#"+def.getName();

				text += ": ("+localize("#PH_Level")+" " + f_to_s(subsys.level,0) + ")#font#\n";
				text += def.getDescription();
				text += "#r#\n\n#tab:6##c:green#"+localize("#PH_HP")+": " + standardize(subsys.maxHP);
				
				uint hintCount = def.getHintCount();
				for(uint i = 0; i < hintCount; ++i) {
					float val = subsys.getHint(i);
					string@ hintName = def.getHintName(i);
					text += ("#c#\n#tab:6#" + localize("#PH_" + hintName)) + ": ";
					if(val >= 0)
						text += "#c:green#" + standardize(val);
					else
						text += "#c:red#-" + standardize(abs(val));
				}

				if (!canBuildStructures) {
					text += "#c#\n\n#c:red#"+localize("#PL_NoSlots");
					hovered_cost.setVisible(false);
				}
				else {
					hovered_cost.setVisible(true);
				}
				
				hovered_build_panel.setText(text);
				hovered_cost.updateDefaults(subsys);
			}
		}
	}
	
	void hoverShip() {
		hb_panel.setVisible(true);

		int itemHovered = buildShipsList.getHovered();
		if(itemHovered >= 0 && uint(itemHovered) < buildShipsList.getItemCount()) {
			const HullLayout@ temp = layouts.getDesign(itemHovered);
			const HullStats@ stats = temp.getStats();
			string@ text = "#font:frank_12#"+temp.getName();
			text += ": ("+localize("#PH_Scale")+" " + standardize(temp.scale*temp.scale) + ")#font#";
			text += "#r#\n\n#tab:6##c:green#"+localize("#PH_HP")+":#tab:100#" + standardize(stats.getHint("HP"));

			for (uint i = 0; i < shipTooltipHintCount && i < 5; ++i) {
				const string@ name = shipTooltipHints[i];
				float val = stats.getHint(name);

				if(val >= 0.01f) {
					if (name == "Thrust") {
						val /= stats.getHint("Mass");

						text += "\n#c##tab:6#" + localize("#PH_Acceleration") + ":#tab:100#";
						text += "#c:green#" + ftos_nice(val/unitsPerAU, 4) + localize("#LE_AUpss");
					}
					else {
						text += "\n#c##tab:6#" + localize("#PH_" + name) + ":#tab:100#";
						text += "#c:green#" + standardize(val);

						if (name == "Fuel") {
							float use = stats.getHint("FuelUse");
							text += use > 0.f ? " #c:green#(":" #c:red#(-";
							text += standardize(abs(use))+")#c#";
						}
					}
				}
			}

			hovered_build_panel.setText(text);
			hovered_cost.updateDefaults(stats);
			hovered_cost.setVisible(true);
		}
	}

	void hideHoverInfo() {
		hb_panel.setVisible(false);
	}
	/* }}} */
	/* {{{ Planet actions */
	void setUseGovernor(bool use) {
		planet.setUseGovernor(use);
	}

	void setTradeMode(int mode) {
		float val = float(mode);
		planet.toObject().setStateVals(strTradeMode, val, val, val, val);
	}

	void setGovernor(int num) {
		planet.setGovernorType(getActiveEmpire().getBuildList(num));
	}

	void setRepeat(bool repeat) {
		planet.toObject().setRepeatQueue(repeat);
	}

	void setPause(bool pause) {
		planet.toObject().setPauseQueue(pause);
	}

	void buildShip() {
		int itemSelected = buildShipsList.getSelected();
		if(itemSelected >= 0) {
			Object@ pl = planet;
			const HullLayout@ temp = layouts.getDesign(itemSelected);

			if (ctrlKey) {
				multiBuild(pl, temp);
			}
			else {
				int buildCount = shiftKey ? 5 : 1;
				pl.makeShip(temp, buildCount);
			}
		}
	}

	void buildStructure() {
		int itemSelected = buildStructsList.getSelected();
		if(itemSelected >= 0 && canBuildStructures) {
			const subSystemDef@ temp = planet.toObject().getOwner().getSubSysData(buildIDs[itemSelected]).type;

			if (ctrlKey) {
				multiBuild(planet, temp);
			}
			else {
				int buildCount = shiftKey ? 5 : 1;
				planet.buildStructure(temp, buildCount);
			}
		}
	}

	void prevPlanet() {
		if (planet is null)
			return;

		SysObjList objects;
		objects.prepare(planet.toObject().getParent().toSystem());
		
		Planet@ newPlanet;
		for(uint i = 0; i < objects.childCount; ++i) {
			Object@ obj = objects.getChild(i);
			Planet@ thisPlanet = @obj;
			if(thisPlanet is null)
				continue;
			if(thisPlanet is planet) {
				if(newPlanet is null) {
					for(uint p = objects.childCount - 1; p > i; --p) {
						@obj = objects.getChild(p);
						@thisPlanet = @obj;
						if(@thisPlanet != null && obj.getOwner() is getActiveEmpire()) {
							if(isSelected(planet.toObject()))
								selectObject(thisPlanet.toObject());
							setPlanet(thisPlanet);
							return;
						}
					}
				}
				else {
					if(isSelected(planet.toObject()))
						selectObject(newPlanet.toObject());
					setPlanet(newPlanet);
					return;
				}
			}
			else if(obj.getOwner() is getActiveEmpire()) {
				@newPlanet = @obj;
			}
		}
		
		objects.prepare(null);
	}

	void nextPlanet() {
		if (planet is null)
			return;

		SysObjList objects;
		objects.prepare(planet.toObject().getParent().toSystem());
		
		bool searchingForThis = true;
		for(uint i = 0; i < objects.childCount; ++i) {
			Object@ obj = objects.getChild(i);
			Planet@ thisPlanet = @obj;
			if(thisPlanet is null)
				continue;
			if(thisPlanet is planet) {
				searchingForThis = false;
				continue;
			}
			else if(searchingForThis == false && obj.getOwner() is getActiveEmpire()) {
				if(isSelected(planet.toObject()))
					selectObject(thisPlanet.toObject());
				setPlanet(thisPlanet);
				return;
			}
		}
		
		//Found the current planet, but found no future planets, go with the first planet instead
		if(searchingForThis == false) {
			for(uint i = 0; i < objects.childCount; ++i) {
				Object@ obj = objects.getChild(i);
				Planet@ thisPlanet = @obj;
				if(@thisPlanet != null && obj.getOwner() is getActiveEmpire()) {
					if(isSelected(planet.toObject()))
						selectObject(thisPlanet.toObject());
					setPlanet(thisPlanet);
					return;
				}
			}
		}
		
		objects.prepare(null);
	}
	/* }}} */
};
/* }}} */
/* {{{ Dialog callbacks */
void loadPlanetQueue(Planet@ pl) {
	loadPlanetQueue(pl.toObject());
}

void loadPlanetQueue(Object@ pl) {
	addSingleImportDialog(localize("#PL_QUEUE")+":", localize("#load"), "Queues", LoadQueue(pl));
}

class LoadQueue : SingleImportDialogCallback {
	Object@ obj;

	LoadQueue(Object@ Obj) {
		@obj = Obj;
	}

	void call(SingleImportDialog@ dialog, string@ text) {
		if (obj.getOwner() is getActiveEmpire())
			loadQueue(obj, text);
	}
}

void savePlanetQueue(Object@ pl) {
	string@ value = pl.getName();
	value += " ";
	value += localize("#PL_QUEUE");

	addEntryDialog(localize("#PL_QUEUE_NAME"), value, localize("#save"), SaveQueue(pl));
}

class SaveQueue : EntryDialogCallback {
	Object@ obj;

	SaveQueue(Object@ Obj) {
		@obj = Obj;
	}

	void call(EntryDialog@ dialog, string@ text) {
		if (obj.getOwner() is getActiveEmpire())
			saveQueue(obj, text);
	}
}

/* }}} */
/* {{{ Galactic capitol data */
float gc_mtl = 0.f, gc_elc = 0.f, gc_adv = 0.f, gc_fud = 0.f;
const Empire@ lastEmpire = null;

void updateGC(){
	if (lastEmpire !is getActiveEmpire()) {
		@lastEmpire = getActiveEmpire();
		const subSystemDef@ def = getSubSystemDefByName("GalacticCapital");

		SubSystemFactory factory;
		factory.objectScale = 10.f;
		factory.objectSizeFactor = 10.f;

		if(factory.generateSubSystems(def, null)) {
			gc_mtl = factory.active.getHint("MtlGen");
			gc_elc = factory.active.getHint("ElecGen");
			gc_adv = factory.active.getHint("AdvGen");
			gc_fud = factory.active.getHint("FoodGen");
		}
	}
}
/* }}} */

PlanetWindowHandle@[] wins;
dim2di defaultSize;

Color pinnedCol;
Color unpinnedCol;

void triggerPlanetWin(Planet@ pl, bool bringToFront) {
	showPlanetWindow(pl);
}

recti getPlanetWindowPosition(dim2di size) {
	if (wins.length() == 0)
		return makeScreenCenteredRect(size);

	return recti(wins[wins.length()-1].getPosition() + pos2di(30, 30), size);
}

GuiElement@ getPlanetWindow() {
	if (wins.length() == 0)
		return null;
	return wins[0].ele;
}

void createPlanetWindow(Planet@ pl) {
	recti pos = getPlanetWindowPosition(defaultSize);
	uint n = wins.length();
	wins.resize(n+1);
	@wins[n] = PlanetWindowHandle(pos);
	wins[n].bringToFront();

	if (pl !is null) {
		wins[n].setPlanet(pl);
		wins[n].setPinned(true);
	}
	else {
		wins[n].findPlanet();
	}
}

void showPlanetWindow(Planet@ pl) {
	if (pl is null) {
		createPlanetWindow(null);
		return;
	}

	// Try to find a window with this pltem
	for (uint i = 0; i < wins.length(); ++i) {
		if (wins[i].isPinned() && wins[i].getPlanet() is pl) {
			wins[i].setVisible(true);
			wins[i].bringToFront();
			return;
		}

		if (!wins[i].isPinned() && !wins[i].isVisible()) {
			wins[i].setVisible(true);
			wins[i].setPlanet(pl);
			wins[i].setPinned(true);
			wins[i].bringToFront();
			return;
		}
	}

	// If none found, create a new window
	createPlanetWindow(pl);
}

void closePlanetWindow(PlanetWindow@ win) {
	int index = findPlanetWindow(win);
	if (index < 0) return;

	if (wins.length() > 1) {
		wins[index].remove();
		wins.erase(index);
	}
	else {
		wins[index].setVisible(false);
		wins[index].setPinned(false);
	}
	setGuiFocus(null);
}

void togglePlanetWindow() {
	// Toggle all windows to a particular state
	bool anyVisible = false;
	for (uint i = 0; i < wins.length(); ++i)
		if (wins[i].isVisible())
			anyVisible = true;
	togglePlanetWindow(!anyVisible);
}

void togglePlanetWindow(bool show) {
	if (shiftKey || wins.length() == 0) {
		createPlanetWindow(null);
	}
	else {
		for (uint i = 0; i < wins.length(); ++i) {
			wins[i].setVisible(show);
			if (show)
				wins[i].bringToFront();
		}
	}
}

bool TogglePlanetWin(const GUIEvent@ evt) {
	if (evt.EventType == GEVT_Clicked) {
		togglePlanetWindow();
		return true;
	}
	return false;
}

bool TogglePlanetWin_key(uint8 flags) {
	if (flags & KF_Pressed != 0) {
		togglePlanetWindow();
		return true;
	}
	return false;
}

int findPlanetWindow(PlanetWindow@ win) {
	for (uint i = 0; i < wins.length(); ++i)
		if (wins[i].script is win)
			return i;
	return -1;
}

void setPlVisible(bool vis) {
	pw_restore_pw.setVisible(vis);
}

GuiButton@ pw_restore_pw;
void init() {
	// Initialize some constants
	unpinnedCol = Color(64, 255, 255, 255);
	pinnedCol = Color(218, 128, 128, 255);

	defaultSize = dim2di(768, 512);

	initSkin();

	// Bind toggle key
	bindFuncToKey("F2", "script:TogglePlanetWin_key");

	// Create top bar button
	int width = getScreenWidth();
	@pw_restore_pw = GuiButton(recti(pos2di(width / 2 - 150, 0), dim2di(100, 25)), null, null);
	pw_restore_pw.setSprites("TB_PlanetInfo", 0, 2, 1);
	pw_restore_pw.setAppearance(BA_UseAlpha, BA_Background);
	pw_restore_pw.setAlignment(EA_Center, EA_Top, EA_Center, EA_Top);
	bindGuiCallback(pw_restore_pw, "TogglePlanetWin");
}

void tick(float time) {
	updateGC();

	// Update all windows
	for (uint i = 0; i < wins.length(); ++i) {
		if (wins[i].isVisible()) {
			wins[i].update(time);
		}
	}
}
