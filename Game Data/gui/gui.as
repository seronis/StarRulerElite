#include "~/Game Data/gui/include/gui_sprite.as"
#include "~/Game Data/gui/include/dialog.as"

import void triggerPlanetWin(Planet@ pl, bool bringToFront) from "planet_win";
import void triggerQueueWin(Object@ obj) from "queue_win";
import void triggerUndockWin(Object@ obj) from "undock_win";
import void anchorToMouse(GuiElement@) from "gui_lib";
import void ToggleEconomyReport() from "economy_report";
import void showSystemWindow(System@ sys) from "sys_win";
import void toggleEscapeMenu() from "escape_menu";
import void triggerContextMenu(Object@) from "context_menu";
import bool isContextMenuUp() from "context_menu";
import void createLogWindow() from "log_win";
import void toggleCivilActsWin() from "civil_acts_win";

const float unitsPerAU = 1000.f;
const string@ strOre = "Ore";

GuiExtText@ empireMessages;
GuiImage@ empMsgBG;

//Nearby overlay elements
GuiImage@ glowLine;
GuiExtText@ nrov_name, nrov_hpTag;
GuiBar@ nrov_hpBar;
GuiExtText@ nrov_build, clock;

GuiExtText@ mouseOverlay;
GuiStaticText@ speedIndicator;

GuiExtText@ bankAdvp, bankElec, bankMetl, bankOres, bankScrp;
GuiExtText@ bankFood, bankFuel, bankAmmo, bankGuds, bankLuxs;

float prevAdvp = -1, prevElec = -1, prevMetl = -1, prevOres = -1, prevScrp = -1;
float prevFood = -1, prevFuel = -1, prevAmmo = -1, prevGuds = -1, prevLuxs = -1;

float rateAdvp = -1, rateElec = -1, rateMetl = -1, rateOres = -1, rateScrp = -1;
float rateFood = -1, rateFuel = -1, rateAmmo = -1, rateGuds = -1, rateLuxs = -1;

double prevBankUpdate = 0;
float bankCounter = 0, prevSpeed = 0;
bool bankMode = false;

double em_lastMsg = -1;
double em_lastVisMsg = -1;

int gameShipLimit;

GuiImage@ tickerBG;
GuiStaticText@ tickerTop, tickerResETA, tickerResRate, tickerTopPercent;
GuiExtText@ shipLimit;

GuiButton@ msgLog, msgExpand, msgShrink, civActs, bankToggle, econReportButton, speedUpButton, slowDownButton, pauseButton;

GuiButton@[] filterButtons;
const string[] filters = {"war", "research", "diplomacy", "build", "misc"};
const bool[] filterState = {true, true, true, false, true};

pos2di msgShrinkPos(0,0);

string@ standardize_nice(float val) {
	if (val > 0.0001f)
		return standardize(val);
	else
		return "0.00";
}

string@ time_to_s(float time) {
	float hours = floor(time / 60.f / 60.f);
	float minutes = floor((time % (60.f * 60.f)) / 60.f);
	float seconds = floor(time % 60.f);

	if (hours > 0) {
		if (minutes > 0) {
			return combine(f_to_s(hours, 0), "h ",f_to_s(minutes, 0), "m");
		}
		else {
			return f_to_s(hours, 0) + "h";
		}
	}
	else if (minutes > 0) {
		return f_to_s(minutes, 0) + "m";
	}
	else {
		return f_to_s(seconds, 0) + "s";
	}
}

void onClick(Object@ obj) {
	// Shift adds to selection
	if (shiftKey) {
		addSelectedObject(obj);
	}
	// Control toggles selection
	else if (ctrlKey) {
		if (isSelected(obj))
			deselectObject(obj);
		else
			addSelectedObject(obj);
	}
	else {
		// If there is a fleet, select the entire fleet first of all
		if (obj.getOwner() is getActiveEmpire()) {
			HulledObj@ ship = obj;
			if (ship !is null) {
				ObjectLock lock(obj);
				Fleet@ fleet = ship.getFleet();

				if (fleet !is null) {
					// If the fleet is already selected, select only this ship
					if (getSelectedObject(getSubSelection()) is obj) {
						selectObject(obj);
						return;
					}

					// If the fleet is not selected, select all ships in it
					uint cnt = fleet.getMemberCount();

					selectObject(null);
					addSelectedObject(fleet.getCommander());
					for (uint i = 0; i < cnt; ++i)
						addSelectedObject(fleet.getMember(i));

					uint selCnt = getSelectedObjectCount();
					for (uint i = 0; i < selCnt; ++i) {
						if (getSelectedObject(i) is obj)
							setSubSelection(i);
					}
					return;
				}
			}
		}

		// If there's no fleet, just select the object
		selectObject(obj);
	}
}

void onDoubleClick(Object@ obj) {
	// If we double-click a fleet leader, select only the fleet leader
	if (obj.getOwner() is getActiveEmpire()) {
		HulledObj@ ship = obj;
		if (ship !is null) {
			ObjectLock lock(obj);
			Fleet@ fleet = ship.getFleet();

			if (fleet !is null && fleet.getCommander() is obj) {
				selectObject(obj);
				return;
			}
		}
	}

	// Open planet window where appropriate
	Planet@ pl = obj;
	if(@pl != null) {
		if (obj.getOwner() is getActiveEmpire())
			triggerPlanetWin(pl, true);
		return;
	}

	// Open system window where appropriate
	if(obj.toSystem() !is null) {
		showSystemWindow(obj.toSystem());
		return;
	}
	else if(obj.toStar() !is null) {
		showSystemWindow(obj.getCurrentSystem());
		return;
	}

	// Open the queue management window where appropriate
	HulledObj@ ship = obj;
	if (ship !is null && obj.getOwner() is getActiveEmpire()) {
		if (ship.getHull().hasSystemWithTag("BuildBay")) {
			triggerQueueWin(obj);
			return;
		}
	}

	setCameraFocus(obj);
}

void onBoxSelect(Object@ obj) {
	addSelectedObject(obj);
}

void onPaintSelect(Object@ obj) {
	addSelectedObject(obj);
}

void onCycleSelection() {
	uint cnt = getSelectedObjectCount();
	if (cnt == 0)
		return;
	setSubSelection((getSubSelection() + 1) % cnt);
}

void onRightClick(Object@ obj) {
	triggerContextMenu(obj);
}

void onManageQueue(Object@ obj) {
	triggerQueueWin(obj);
}

void onManageDocked(Object@ obj) {
	triggerUndockWin(obj);
}

void onTriggerEscapeMenu() {
	toggleEscapeMenu();
}

void setTicker(string@ top, string@ eta) {
	tickerTopPercent.setText(top);
	tickerTop.setText(top);
	tickerResETA.setText(eta);
	tickerResRate.setText(null);
}

void setTicker(string@ top, string@ eta, string@ res) {
	tickerTopPercent.setText(top);
	tickerTop.setText(top);
	dim2di textSize = getTextDimension(tickerTop.getText());
	tickerTop.setSize(dim2di(textSize.width, tickerTop.getSize().height));
	tickerTopPercent.setSize(dim2di(0.01 * textSize.width, tickerTopPercent.getSize().height));

	tickerResETA.setText(eta);
	tickerResETA.setToolTip(res);
	tickerResRate.setText(res);
	tickerResRate.setToolTip(eta);
}

void setTickerPercent(float perc, Color col) {
	dim2di textSize = getTextDimension(tickerTopPercent.getText());
	tickerTopPercent.setSize(dim2di(perc * textSize.width, tickerTopPercent.getSize().height));
	tickerTop.setSize(dim2di(textSize.width, tickerTopPercent.getSize().height));
	tickerTopPercent.setColor(col);
}

GuiScripted@[] top_icos(10);

bool speedUp(const GUIEvent@ evt) {
	if (evt.EventType == GEVT_Clicked) {
		float speed = getGameSpeedFactor();

		if (speed == 0) {
			speed = 1.f;
		} 
		else if (speed < 0.99f) {
			speed *= 2.f;
		}
		else if (speed < 1.01f) {
			speed = 2.f;
		}
		else { 
			speed += 2.f;
			speed = floor(speed/2.f)*2.f;
	    }

		setGameSpeedFactor(speed);
	} else if (evt.EventType == GEVT_Right_Clicked) {
		setGameSpeedFactor(10.f);
	}
	return false;
}

bool slowDown(const GUIEvent@ evt) {
	if (evt.EventType == GEVT_Clicked) {
		float speed = getGameSpeedFactor();

		if (speed > 0.06f) {
			if (speed < 1.01f) {
				speed /= 2.f;
			}
			else if (speed < 2.01f) {
				speed = 1.f;
			}
			else { 
				speed -= 2.f;
				speed = ceil(speed/2.f)*2.f;
			}
		}

		setGameSpeedFactor(speed);
	} else if (evt.EventType == GEVT_Right_Clicked) {
		setGameSpeedFactor(0.03f);
	}
	return false;
}

bool doPause(const GUIEvent@ evt) {
	if (evt.EventType == GEVT_Clicked) {
		pauseGame();
	} else if (evt.EventType == GEVT_Right_Clicked) {
		setGameSpeedFactor(1.f);
	}
	return false;
}

void setMessagesVisible(bool visible) {
	empMsgBG.setVisible(visible);
}

void setTickerVisible(bool visible) {
	tickerBG.setVisible(visible);
}

void setTickerResearchVisible(bool visible) {
	tickerTop.setVisible(visible);
	tickerTopPercent.setVisible(visible);
	tickerResETA.setVisible(visible);
	tickerResRate.setVisible(visible);
}

bool toggleResRateETA(const GUIEvent@ evt) {
	if(evt.EventType == GEVT_Clicked) {
		bool visible = tickerResETA.isVisible();
		tickerResETA.setVisible(!visible);
		tickerResRate.setVisible(visible);
	}
	return false;
}

void init() {
	int width = getScreenWidth();

	@empMsgBG = GuiImage( pos2di(width / 2 - 250, 26), "message_bg", null);
	empMsgBG.setAlignment(EA_Center, EA_Top, EA_Center, EA_Top);

	@glowLine = GuiImage( pos2di(0,0), "glow_line", null);
	@nrov_name  = GuiExtText( recti(pos2di(0,0), dim2di(115,15)), null ); nrov_name.setShadow(Color(255,0,0,0));
	@nrov_build = GuiExtText( recti(pos2di(0,0), dim2di(200,15)), null);  nrov_build.setShadow(Color(255,0,0,0));
	@nrov_hpTag = GuiExtText( recti(pos2di(0,0), dim2di(46,15)), null);   nrov_hpTag.setShadow(Color(255,0,0,0)); nrov_hpTag.setText("#align:right#HP:");
	@nrov_hpBar = GuiBar( recti( pos2di(0,0), dim2di(50,7)), null);       nrov_hpBar.set( Color(255,0,255,0), Color(255,255,0,0), true, 1);
	hideNearOverlay();

	@empireMessages = GuiExtText(recti( pos2di(8,3), dim2di(500 - 38, 18)), empMsgBG);
	@clock = GuiExtText(recti(pos2di(width-125, 4), dim2di(125, 36)), null);
	clock.setAlignment(EA_Right, EA_Top, EA_Right, EA_Top);

	@speedIndicator = GuiStaticText(recti(pos2di(width-125, 39), dim2di(100, 18)), localize("#paused"), false, false, false, null);
		speedIndicator.setFont("stroked");
		speedIndicator.setAlignment(EA_Right, EA_Top, EA_Right, EA_Top);
	@speedUpButton = GuiButton(getSkinnable("Button"), recti(pos2di(width-14, 43), dim2di(10,10)), ">", null);
		speedUpButton.setAlignment(EA_Right, EA_Top, EA_Right, EA_Top);
	@pauseButton = GuiButton(getSkinnable("Button"), recti(pos2di(width-26, 43), dim2di(10,10)), "|", null);
		pauseButton.setAlignment(EA_Right, EA_Top, EA_Right, EA_Top);
	@slowDownButton = GuiButton(getSkinnable("Button"), recti(pos2di(width-38, 43), dim2di(10,10)), "<", null);
		slowDownButton.setAlignment(EA_Right, EA_Top, EA_Right, EA_Top);

	gameShipLimit = int(getGameSetting("LIMIT_SHIPS", 0));
	if (gameShipLimit > 0)
		@shipLimit = GuiExtText(recti(8, 108, 234, 132), null);

	bool client = isClient();
	speedUpButton.setVisible(!client);
	slowDownButton.setVisible(!client);
	pauseButton.setVisible(!client);

	bindGuiCallback(speedUpButton, "speedUp");
	bindGuiCallback(slowDownButton, "slowDown");
	bindGuiCallback(pauseButton, "doPause");

	msgShrinkPos = pos2di(500 - 18, 4);

	@msgLog = GuiButton(recti( pos2di(500 - 18 - 17, 4), dim2di(16,16)), null, empMsgBG);
	msgLog.setImage("msg_box_log");
	msgLog.setAlignment(EA_Right, EA_Bottom, EA_Right, EA_Bottom);
	@msgExpand = GuiButton(recti( pos2di(500 - 18, 4), dim2di(16,16)), null, empMsgBG);
	msgExpand.setImage("msg_box_expand");
	@msgShrink = GuiButton(recti( pos2di(500 - 18, 4), dim2di(16,16)), null, empMsgBG);
	msgShrink.setImage("msg_box_shrink");
	msgShrink.setVisible(false);
	msgShrink.setAlignment(EA_Right, EA_Bottom, EA_Right, EA_Bottom);

	filterButtons.resize(filters.length());
	int filterID = reserveGuiID();
	for (uint i = 0; i < filters.length(); ++i) {
		@filterButtons[i] = GuiButton(getSkinnable("ToggleButton"), recti(pos2di(4 + 52 * i, 4), dim2di(48, 16)), localize("#MT_Filter_"+filters[i]), empMsgBG);
		filterButtons[i].setToolTip(localize("#MTTT_Filter_"+filters[i]));
		filterButtons[i].setToggleButton(true);
		filterButtons[i].setPressed(filterState[i]);
		filterButtons[i].setVisible(false);
		filterButtons[i].setID(filterID);
		filterButtons[i].setAlignment(EA_Left, EA_Bottom, EA_Left, EA_Bottom);
	}

	bindGuiCallback(filterID, "refreshMsgs");
	bindGuiCallback(msgExpand, "expandMsgBox");
	bindGuiCallback(msgShrink, "shrinkMsgBox");
	bindGuiCallback(msgLog, "openLogWindow");

	@mouseOverlay = GuiExtText(recti( pos2di(-1,-1), dim2di(300, 200)), null);
	mouseOverlay.setNoclipped(true);

	@tickerBG = GuiImage( pos2di(2,4), "elite_econ_ticker", null);
	@tickerTop        = GuiStaticText( recti( pos2di(  8, 6), dim2di(200, 15) ), null, false, false, false, tickerBG);
	@tickerTopPercent = GuiStaticText( recti( pos2di(  8, 6), dim2di( 20, 15) ), null, false, false, false, tickerBG);

	@tickerResETA     = GuiStaticText( recti( pos2di(250, 6), dim2di( 96, 15) ), null, false, false, false, tickerBG);
	@tickerResRate    = GuiStaticText( recti( pos2di(250, 6), dim2di( 96, 15) ), null, false, false, false, tickerBG);

	tickerResETA.setTextAlignment( EA_Right, EA_Top);
	tickerResRate.setTextAlignment(EA_Right, EA_Top);
//	bindGuiCallback(tickerResRate, "toggleResRateETA");
//	bindGuiCallback(tickerResETA, "toggleResRateETA");
	tickerResRate.setVisible(false);

	tickerTop.setColor( Color(255, 255, 255, 255) );
	tickerResETA.setColor( Color(255, 255, 255, 255) );
	tickerResRate.setColor( Color(255, 255, 255, 255) );

	int h1 = 48, v1 = 16; //size of value fields
	int h2 = 16, v2 = 16; //size of icons
	int ho = 8, vo = 32;  //margins from window edge
	int vb = 4;			  //verticle space between elements

	int hb = 4 + h2;	  //horizontal space between elements
	@bankAdvp = GuiExtText(recti(pos2di(ho+(h1+hb)*0, vo+(v1+vb)*0), dim2di(h1, v1)), tickerBG);
	@bankElec = GuiExtText(recti(pos2di(ho+(h1+hb)*1, vo+(v1+vb)*0), dim2di(h1, v1)), tickerBG);
	@bankMetl = GuiExtText(recti(pos2di(ho+(h1+hb)*2, vo+(v1+vb)*0), dim2di(h1, v1)), tickerBG);
	@bankOres = GuiExtText(recti(pos2di(ho+(h1+hb)*3, vo+(v1+vb)*0), dim2di(h1, v1)), tickerBG);
	@bankScrp = GuiExtText(recti(pos2di(ho+(h1+hb)*4, vo+(v1+vb)*0), dim2di(h1, v1)), tickerBG);

	@bankFood = GuiExtText(recti(pos2di(ho+(h1+hb)*0, vo+(v1+vb)*1), dim2di(h1, v1)), tickerBG);
	@bankFuel = GuiExtText(recti(pos2di(ho+(h1+hb)*1, vo+(v1+vb)*1), dim2di(h1, v1)), tickerBG);
	@bankAmmo = GuiExtText(recti(pos2di(ho+(h1+hb)*2, vo+(v1+vb)*1), dim2di(h1, v1)), tickerBG);
	@bankGuds = GuiExtText(recti(pos2di(ho+(h1+hb)*3, vo+(v1+vb)*1), dim2di(h1, v1)), tickerBG);
	@bankLuxs = GuiExtText(recti(pos2di(ho+(h1+hb)*4, vo+(v1+vb)*1), dim2di(h1, v1)), tickerBG);

	ho = 10 + h1;
	hb = 4 + h1;
	GuiScripted@ ico;
	@ico = GuiScripted(recti(pos2di(ho+(h2+hb)*0, vo+(v2+vb)*0), dim2di(16, 16)), gui_sprite("hard_resource_icons", 0) , tickerBG);
	ico.setToolTip(localize("#GBR_advparts"));
	@top_icos[0] = @ico;

	@ico = GuiScripted(recti(pos2di(ho+(h2+hb)*1, vo+(v2+vb)*0), dim2di(16, 16)), gui_sprite("hard_resource_icons", 1) , tickerBG);
	ico.setToolTip(localize("#GBR_electronics"));
	@top_icos[1] = @ico;

	@ico = GuiScripted(recti(pos2di(ho+(h2+hb)*2, vo+(v2+vb)*0), dim2di(16, 16)), gui_sprite("hard_resource_icons", 2) , tickerBG);
	ico.setToolTip(localize("#GBR_metals"));
	@top_icos[2] = @ico;

	@ico = GuiScripted(recti(pos2di(ho+(h2+hb)*3, vo+(v2+vb)*0), dim2di(16, 16)), gui_sprite("hard_resource_icons", 3) , tickerBG);
	ico.setToolTip(localize("#GBR_ore"));
	@top_icos[3] = @ico;

	@ico = GuiScripted(recti(pos2di(ho+(h2+hb)*4, vo+(v2+vb)*0), dim2di(16, 16)), gui_sprite("hard_resource_icons", 4) , tickerBG);
	ico.setToolTip(localize("#GBR_scrap"));
	@top_icos[4] = @ico;

	@ico = GuiScripted(recti(pos2di(ho+(h2+hb)*0, vo+(v2+vb)*1), dim2di(16,16)), gui_sprite("hard_resource_icons", 5), tickerBG);
	ico.setToolTip(localize("#GBR_food"));
	@top_icos[5] = @ico;

	@ico = GuiScripted(recti(pos2di(ho+(h2+hb)*1, vo+(v2+vb)*1), dim2di(16, 16)), gui_sprite("hard_resource_icons", 6) , tickerBG);
	ico.setToolTip(localize("#GBR_fuel"));
	@top_icos[6] = @ico;

	@ico = GuiScripted(recti(pos2di(ho+(h2+hb)*2, vo+(v2+vb)*1), dim2di(16,16)), gui_sprite("hard_resource_icons", 7), tickerBG);
	ico.setToolTip(localize("#GBR_ammo"));
	@top_icos[7] = @ico;

	@ico = GuiScripted(recti(pos2di(ho+(h2+hb)*3, vo+(v2+vb)*1), dim2di(16,16)), gui_sprite("hard_resource_icons", 8), tickerBG);
	ico.setToolTip(localize("#GBR_goods"));
	@top_icos[8] = @ico;

	@ico = GuiScripted(recti(pos2di(ho+(h2+hb)*4, vo+(v2+vb)*1), dim2di(16,16)), gui_sprite("hard_resource_icons", 9), tickerBG);
	ico.setToolTip(localize("#GBR_luxuries"));
	@top_icos[9] = @ico;



	@bankToggle = GuiButton(recti(pos2di(356, 32), dim2di(22,16)), null, tickerBG);
	bankToggle.setAppearance(BA_UseAlpha, BA_Background);
	bankToggle.setSprites("economy_btn_mode", 3, 5, 4);
	bankToggle.setToolTip(localize("#TT_bankToggle"));
	bindGuiCallback(bankToggle, "toggleBankDisplay");

	@civActs = GuiButton(recti(pos2di(356, 48), dim2di(22,16)), null, tickerBG);
	civActs.setAppearance(BA_UseAlpha, BA_Background);
	civActs.setSprites("economy_btn_mode", 6, 8, 7);
	civActs.setToolTip(localize("#TT_civActs"));
	bindGuiCallback(civActs, "openCivilActs");

	@econReportButton = GuiButton(recti(pos2di(356, 64), dim2di(22,16)), null, tickerBG);
	econReportButton.setAppearance(BA_UseAlpha, BA_Background);
	econReportButton.setSprites("economy_btn_report", 0, 2, 1);
	econReportButton.setToolTip(localize("#TT_econReport"));
	bindGuiCallback(econReportButton, "openEconReport");

	bindGuiCallback(empMsgBG, "hoverMsgBox");
	bindGuiCallback(empireMessages, "hoverMsgBox");
}

void setBankButtonsVisible(bool vis) {
	econReportButton.setVisible(vis);
	bankToggle.setVisible(vis);
}

void setCivActsButtonVisible(bool vis) {
	civActs.setVisible(vis);
}

uint em_curSize = 0;
bool msgMousedOver = false;

bool hoverMsgBox(const GUIEvent@ evt) {
	if (evt.EventType == GEVT_Mouse_Over)
		msgMousedOver = true;
	else if (evt.EventType == GEVT_Mouse_Left)
		msgMousedOver = false;
	return false;
}

bool refreshMsgs(const GUIEvent@ evt) {
	if(evt.EventType == GEVT_Clicked) {
		em_lastMsg = -1;
	}
	return false;
}

bool openLogWindow(const GUIEvent@ evt) {
	if (evt.EventType == GEVT_Clicked) {
		createLogWindow();
	}
	return false;
}

bool expandMsgBox(const GUIEvent@ evt) {
	if(evt.EventType == GEVT_Clicked) {
		if(em_curSize == 0) {
			empMsgBG.setImage("message_bg_5line");
			empMsgBG.setSize( dim2di(500, 96) );
			empMsgBG.bringToFront();
			empireMessages.setSize( dim2di(500 - 18, 96 - 6) );

			for (uint i = 0; i < filters.length(); ++i)
				filterButtons[i].setVisible(true);
			
			msgShrink.setVisible(true);
			em_curSize = 1;

			msgLog.setPosition(pos2di(msgLog.getPosition().x, msgShrink.getPosition().y));

			return true;
		}
		else if(em_curSize == 1) {
			empMsgBG.setImage("message_bg_14line");
			empMsgBG.setSize( dim2di(500, 240) );
			empMsgBG.bringToFront();
			empireMessages.setSize( dim2di(500 - 18, 240 - 6) );

			for (uint i = 0; i < filters.length(); ++i)
				filterButtons[i].setVisible(true);
			
			msgShrink.setVisible(true);

			msgExpand.setVisible(false);
			em_curSize = 2;
			return true;
		}
	}
	return false;
}

bool shrinkMsgBox(const GUIEvent@ evt) {
	if(evt.EventType == GEVT_Clicked) {
		if(em_curSize == 2) {
			empMsgBG.setImage("message_bg_5line");
			empMsgBG.setSize( dim2di(500, 96) );
			empireMessages.setSize( dim2di(500 - 16, 96 - 6) );

			for (uint i = 0; i < filters.length(); ++i)
				filterButtons[i].setVisible(true);
			
			msgExpand.setVisible(true);
			em_curSize = 1;
			return true;
		}
		else if(em_curSize == 1) {
			empMsgBG.setImage("message_bg");
			empMsgBG.setSize( dim2di(500, 24) );
			empireMessages.setSize( dim2di(500 - 16, 26 - 8) );

			for (uint i = 0; i < filters.length(); ++i)
				filterButtons[i].setVisible(false);
			
			msgShrink.setVisible(false);

			msgExpand.setVisible(true);
			em_curSize = 0;
			return true;
		}
	}
	return false;
}

uint lastSizeMode = 255;

string@ getStatePrefix(float delta, float amn) {
	if (amn < -0.001f)
		return "#a:r##c:faa#-";
	if (delta > 0)
		return "#a:r##c:aca#";
	else if (delta < 0)
		return "#a:r##c:caa#";
	else
		return "#a:r#";
}

string@ getRatePrefix(float delta) {
	if(delta > 0)
		return "#a:r##c:aca#+";
	else if(delta < 0)
		return "#a:r##c:caa#-";
	else
		return "#a:r#";
}

void updateBankState(float& prev, float now, float& rate, float duration) {
	rate = (now - prev) / duration;
	prev = now;
}

bool openEconReport(const GUIEvent@ evt) {
	if(evt.EventType == GEVT_Clicked) {
		ToggleEconomyReport();
	}
	return false;
}

bool toggleBankDisplay(const GUIEvent@ evt) {
	if(evt.EventType == GEVT_Clicked) {
		bankMode = !bankMode;
		bankCounter = 1.f;

		if (bankMode)
			bankToggle.setSprites("economy_btn_mode", 0, 2, 1);
		else
			bankToggle.setSprites("economy_btn_mode", 3, 5, 4);
	}
	return false;
}

bool openCivilActs(const GUIEvent@ evt) {
	if(evt.EventType == GEVT_Clicked) {
		toggleCivilActsWin();
	}
	return false;
}

int lastMins = -1, lastGameMins = -1;

bool isCategoryActive(string@ cat) {
	int len = filters.length();
	for (int i = 0; i < len; ++i) {
		if (!filterButtons[i].isPressed() && cat == filters[i])
			return false;
	}
	return true;
}

bool isPriorityActive(int prior) {
	return prior >= 0;
}

float msgMouseDelay = 0.f;
uint notifyThrottle = 0;

void tick(float time) {	
	if (notifyThrottle > 0)
		--notifyThrottle;

	Empire@ emp = getActiveEmpire();
	if(emp.lastMessage > em_lastMsg || lastSizeMode != em_curSize) {
		string@ allMsgs = "";
		EmpireMessages msgs;
		msgs.prepare(emp);
		
		if(msgs.getCount() > 0) {		
			uint lines = em_curSize == 0 ? 1 : em_curSize == 1 ? 4 : 13;
		
			do {
				int prior = msgs.getPriority();
				string@ cat = msgs.getCategory();
				if (isCategoryActive(cat) && isPriorityActive(prior)) {
					double time = msgs.getTime();
					if (time > em_lastMsg)
						msgMouseDelay = 0.f;
					if (time > em_lastVisMsg && notifyThrottle == 0) {
						if (em_lastVisMsg > 0)
							playSound("msg_notify");

						em_lastVisMsg = time;
						notifyThrottle = 6;
					}
					allMsgs += (msgs.getMsg() + "\n");
					lines -= 1;
				}
			} while(lines > 0 && msgs.nextMsg());
		}
		
		msgs.prepare(null);
		empireMessages.setText(allMsgs);
		
		em_lastMsg = emp.lastMessage;
		lastSizeMode = em_curSize;
	}
	
	//In one-line mode, fade out older messages
	if(em_curSize == 0 && !msgMousedOver) {
		float delay = msgMouseDelay;
		float fade = 1;

		if(delay > 5.f)
			if(delay >= 7.f)
				fade = 0.6f;
			else
				fade = 0.6f + 0.4f * (7.f - delay) / 2.f;

		empireMessages.setAlpha(fade);
	}
	else {
		empireMessages.setAlpha(1);
		msgMouseDelay = 0.f;
	}

	if (getActiveEmpire().hasTraitTag("disable_civil_acts")) {
		civActs.setSprites("economy_btn_mode", 9, 9, 9);
		civActs.setEnabled(false);
	}
	else {
		civActs.setSprites("economy_btn_mode", 6, 8, 7);
		civActs.setEnabled(true);
	}

	msgMouseDelay += time;

	//Update empire bank numbers
	bankCounter += time;

	//Update once per second
	if (bankCounter >= 1.f) {
		//Unless the game is paused
		if(prevBankUpdate != gameTime) {
			float since = float(gameTime - prevBankUpdate);
			prevBankUpdate = gameTime;
			
			updateBankState(prevAdvp, emp.getStat("AdvParts"),    rateAdvp, since);
			updateBankState(prevElec, emp.getStat("Electronics"), rateElec, since);
			updateBankState(prevMetl, emp.getStat("Metals"),      rateMetl, since);
			updateBankState(prevOres, emp.getStat("Ores"),        rateOres, since);
			updateBankState(prevScrp, emp.getStat("Scrp"),        rateScrp, since);
			updateBankState(prevFood, emp.getStat("Food"),        rateFood, since);
			updateBankState(prevFuel, emp.getStat("Fuel"),        rateFuel, since);
			updateBankState(prevAmmo, emp.getStat("Ammo"),        rateAmmo, since);
			updateBankState(prevGuds, emp.getStat("Guds"),        rateGuds, since);
			updateBankState(prevLuxs, emp.getStat("Luxs"),        rateLuxs, since);

			if (!bankMode) {
				bankAdvp.setText( getStatePrefix(rateAdvp, prevAdvp) +standardize(abs(prevAdvp)));
				bankElec.setText( getStatePrefix(rateElec, prevElec) +standardize(abs(prevElec)));
				bankMetl.setText( getStatePrefix(rateMetl, prevMetl) +standardize(abs(prevMetl)));
				bankOres.setText( getStatePrefix(rateOres, prevOres) +standardize(abs(prevOres)));
				bankScrp.setText( getStatePrefix(rateScrp, prevScrp) +standardize(abs(prevScrp)));
				bankFood.setText( getStatePrefix(rateFood, prevFood) +standardize(abs(prevFood)));
				bankFuel.setText( getStatePrefix(rateFuel, prevFuel) +standardize(abs(prevFuel)));
				bankAmmo.setText( getStatePrefix(rateAmmo, prevAmmo) +standardize(abs(prevAmmo)));
				bankGuds.setText( getStatePrefix(rateGuds, prevGuds) +standardize(abs(prevGuds)));
				bankLuxs.setText( getStatePrefix(rateLuxs, prevLuxs) +standardize(abs(prevLuxs)));
			}
			else {
				bankAdvp.setText( getRatePrefix(rateAdvp) +standardize(abs(rateAdvp)));
				bankElec.setText( getRatePrefix(rateElec) +standardize(abs(rateElec)));
				bankMetl.setText( getRatePrefix(rateMetl) +standardize(abs(rateMetl)));
				bankOres.setText( getRatePrefix(rateOres) +standardize(abs(rateOres)));
				bankScrp.setText( getRatePrefix(rateScrp) +standardize(abs(rateScrp)));
				bankFood.setText( getRatePrefix(rateFood) +standardize(abs(rateFood)));
				bankFuel.setText( getRatePrefix(rateFuel) +standardize(abs(rateFuel)));
				bankAmmo.setText( getRatePrefix(rateAmmo) +standardize(abs(rateAmmo)));
				bankGuds.setText( getRatePrefix(rateGuds) +standardize(abs(rateGuds)));
				bankLuxs.setText( getRatePrefix(rateLuxs) +standardize(abs(rateLuxs)));
			}

			rateAdvp = rateElec = rateMetl = rateOres = rateScrp = 0.f;
			rateFood = rateFuel = rateAmmo = rateGuds = rateLuxs = 0.f;
		}
		bankCounter = 0.f;
	}

	// Update ship limit
	if (gameShipLimit > 0) {
		int shipCount = int(emp.getStat("Ship"));

		if (shipCount < gameShipLimit) {
			shipLimit.setText(combine(localize("#NG_ShipLimit"),
						"#tab:100#", i_to_s(shipCount), " / ",
						i_to_s(gameShipLimit)));
		}
		else {
			shipLimit.setText(combine("#c:red#",
				combine(localize("#NG_ShipLimit"), "#tab:100#",
				i_to_s(shipCount), " / ", i_to_s(gameShipLimit)), "#c#"));
		}
	}
	
	if(@curObject != null)
		setMouseOverlayText(curObject);
	
	updateNearbyObject(getCameraFocus());

	//Update clock
	float gt = getCurrentGameTime();
	int gtHours = floor(gt / 3600.0);
	int gtMins = floor((gt-gtHours*3600.0) / 60.0);

	int ttime = getCurrentTime();
	int ttHours = floor(ttime / 60.0);
	int ttMins = (ttime-ttHours*60.0);

	//GAH I WANT SPRINTF (HAH, YOU DON'T GET THE MOST UNSTABLE FUNCTION IN EXISTENCE FOR A SCRIPT LANGUAGE)
	
	if(lastMins != ttMins || lastGameMins != gtMins) {
		lastMins = ttMins;
		lastGameMins = gtMins;
	
		string@ teMins = (ttMins >= 10 ? "" : "0")+ttMins;
		string@ geMins = (gtMins >= 10 ? "" : "0")+gtMins;

		clock.setText(combine("#font:stroked#", localize("#time")+": "+ttHours+":"+teMins+"\n"+localize("#gametime")+": "+gtHours+"h:"+geMins+"m", "#font"));
	}

	//Update pause indicator
	float speed = getRealGameSpeedFactor();
	if (speed != prevSpeed) {
		prevSpeed = speed;
		if (speed < 0.01f) {
			speedIndicator.setText(localize("#paused"));
			speedIndicator.setColor(Color(255, 200, 200, 50));
		}
		else {
			speedIndicator.setText(standardize(speed)+"x "+localize("#speed"));

			if (speed  > 1.01f)
				speedIndicator.setColor(Color(255, 55, 200, 55));
			else if (speed < 0.99f)
				speedIndicator.setColor(Color(255, 200, 55, 55));
			else
				speedIndicator.setColor(Color(255, 255, 255, 255));
		}
	}
}

Object@ curObject;

pos2di lastTopRight;

string@ formatDistance(float range) {
	if(range < unitsPerAU)
		return ftos_nice(range / unitsPerAU, 3);
	else
		return standardize(range / unitsPerAU);
}

string@ formatValue(float val, float max, string@ name, Color full, Color empty) {
	Color col = full;
	if(max <= 0)
		max = 1.f;
	col = col.interpolate(empty, val/max);

	return combine(
			combine("\n", name, ": "),
			combine("#c:", col.format(), "#"),
			combine(standardize_nice(val), "/", standardize_nice(max)),
			"#c#"
		);
}

string@ formatValue(int val, int max, string@ name, Color full, Color empty) {
	Color col = full;
	if(max <= 0)
		max = 1;
	col = col.interpolate(empty, float(val)/float(max));

	return combine(
			combine("\n", name, ": "),
			combine("#c:", col.format(), "#"),
			combine(i_to_s(val), "/", i_to_s(max)),
			"#c#"
		);
}

string@ formatState(Object@ obj, string@ state, string@ name, Color full, Color empty, bool reverse) {
	float val = 0.f, max = 0.f, req = 0.f, cargo = 0.f;
	if (obj.getStateVals(state, val, max, req, cargo) && max > 0) {
		if (reverse)
			val = max-val;
		return formatValue(val, max, name, full, empty);
	}
	return "";
}

string@ strJumpDrive = "Jump Drive", strMinRange = "vJumpRangeMin",
		strMaxRange = "vJumpRange", strBankAccess = "BankAccess";
void setMouseOverlayText(Object@ obj) {
	ObjectLock lock(obj);

	@curObject = @obj;
	HulledObj@ hull = obj.toHulledObj();
	Planet@ pl = obj;
	System@ sys = obj;
	System@ curSys = obj.getParent();

	Star@ star = obj;
	if (star !is null)
		@sys = obj.getParent();
	if (sys !is null)
		@curSys = sys;

	Empire@ emp = getActiveEmpire();
	Empire@ owner = obj.getOwner();

	bool explored = curSys !is null && curSys.hasExplored(emp);
	bool sysVisible = curSys !is null && curSys.isVisibleTo(emp);
	bool visible = obj.isVisibleTo(emp);
	
	Color ownerColor = Color(255,255,255,255);
	if (sys !is null) {
		ownerColor = sys.getRingColor();
		ownerColor.A = 255;
	}
	else if (owner !is null) {
		ownerColor = owner.color;
	}

	string@ mo_text = combine("#c:", ownerColor.format(), "#", obj.getName(), "#c#");

	// Ship scale
	if (@hull != null && @hull.getHull() != null)
		mo_text += " ("+standardize(pow(obj.radius, 2))+")";

	// Planet governor
	if (@pl != null && owner is emp)
		if (!pl.usesGovernor())
			mo_text += " ("+localize("#PG_NoGov")+")";
		else
			mo_text += " ("+localize("#PG_"+pl.getGovernorType())+")";

	// Blockaded
	bool blockaded = false;
	if (pl !is null) {
		blockaded = curSys !is null && curSys.isBlockadedFor(owner);
	}
	else if (sys !is null) {
		blockaded = sys.hasPlanets(emp) && sys.isBlockadedFor(emp);
	}
	else if (hull !is null && curSys !is null) {
		if (hull.getHull().hasSystemWithTag(strBankAccess))
			blockaded = curSys.isBlockadedFor(emp);
	}

	if (blockaded)
		mo_text += combine("\n#c:f44#", localize("#MO_Blockade"),"#c#");

	// Hitpoints
	mo_text += formatState(obj, "Damage", localize("#MO_HP"), Color(255, 0, 220, 0), Color(255, 255, 0, 0), true);
	mo_text += formatState(obj, "Shields", localize("#MO_Shields"), Color(255, 80, 180, 200), Color(255, 200, 80, 180), false);
	
	// Other stats
	float used, max;
	obj.getCargoVals(used, max);
	if(max > 0.f)
		mo_text += formatValue(used, max, localize("#MO_Cargo"), Color(0xffCDCDCD), Color(0xff737373));
	obj.getShipBayVals(used, max);
	if(max > 0.f)
		mo_text += formatValue(used, max, localize("#MO_ShipBay"), Color(0xff7DA7D9), Color(0xff605CA8));

	if (pl !is null) {
		if (visible) {
			mo_text += formatState(obj, "Workers", localize("#MO_Population"), Color(0xffa65296), Color(0xffd23323), false);
			mo_text += formatValue(int(pl.getStructureCount()), int(pl.getMaxStructureCount()),
					localize("#MO_Slots"), Color(0xffA67C52), Color(0xff616161));
		}
		else if (explored) {
			mo_text += combine("\n", localize("#MO_Slots"), ": #c:a616161#", f_to_s(pl.getMaxStructureCount(), 0), "#c#");
		}
	}

	if(pl !is null && explored) {
		uint condCnt = pl.getConditionCount();
		if(condCnt > 0) {
			mo_text += combine("\n",localize("#MO_Conditions"),": ");
			for(uint i = 0; i < condCnt; ++i) {
				const PlanetCondition@ cond = pl.getCondition(i);
				if (cond !is null)
					if(i != 0)
						mo_text += ", " + localize("#PC_" + cond.get_id());
					else
						mo_text += localize("#PC_" + cond.get_id());
				else
					error("Planet condition was null: "+i+"/"+condCnt);
			}
		}
	}
	
	if(owner is emp) {
		uint queue = obj.getConstructionQueueSize();
		if(queue > 0) {
			mo_text += "\n"+localize("#MO_Building")+" ";
			string@ cnstr_name = obj.getConstructionName();
			if(@cnstr_name != null)
				mo_text += cnstr_name + " ";
			mo_text += "(" + round(obj.getConstructionProgress() * 100) + "%)";
			if(queue > 1)
				mo_text += "\n  " + (queue - 1) + " "+localize("#more_in_queue");
		}
	}

	if (hull is null) {
		float oreVal = 0.f, oreMax = 0.f, temp = 0.f;
		if (obj.getStateVals("Ore", oreVal, oreMax, temp, temp)) {
			if (visible && oreMax > 0) {
				mo_text += formatValue(oreVal, oreMax, localize("#MO_Ore"), Color(255, 0xC6, 0x9C, 0x6D), Color(255, 0x73, 0x63, 0x57));
			}
			else if (explored) {
				if (oreMax <= 0.1f)
					mo_text += combine("\n", localize("#MO_Ore"), ": #c:736357#0.00#c#");
				else
					mo_text += combine("\n", localize("#MO_Ore"), ": #c:c69c6d#", standardize_nice(oreMax), "#c#");
			}
		}
	}

	// System tags
	if (sys !is null) {
		SystemTags tags;
		tags.prepare(sys);

		if (tags.getCount() > 0) {
			string@ conditions = null;
			do {
				string@ tag = tags.getTag();

				if (explored || sysVisible || tag.beginsWith("Global/")) {
					string@ name = localize(combine("#ST_", tag, "_Name"));
					string@ desc = localize(combine("#ST_", tag, "_Desc"));

					if (name !is null && !name.beginsWith("#ST_")) {
						if (desc !is null && !desc.beginsWith("#ST_"))
							mo_text += combine("\n", name, "\n    ", desc);
						else
							mo_text = combine(mo_text, "\n", name);
					}
				}
			}
			while (tags.next());
		}

		if (!sys.isVisibleTo(emp)) {
			float lastIntel = sys.getLastIntel();
			if (lastIntel > 0) {
				lastIntel = gameTime - lastIntel;
				mo_text += combine("\n", localize("#MO_LastIntel"),
							time_to_s(lastIntel), localize("#MO_Ago"));
			}
		}
	}
	
	// Speed
	if (pl is null || obj.thrust > 0) {
		float speed = obj.velocity.getLength() / unitsPerAU;
		if(speed > 0.001f) {
			string@ speedText;
			if(speed < 0.1f)
				@speedText = f_to_s(speed, 3);
			else if(speed < 1.f)
				@speedText = f_to_s(speed, 2);
			else if(speed < 10.f)
				@speedText = f_to_s(speed, 1);
			else
				@speedText = standardize(speed);
		
			mo_text += "\n"+localize("#MO_Speed")+speedText+localize("#MO_AUps");
		}
	}
	
	// Distance and range meters
	Object@ selected = getSelectedObject(getSubSelection());
	if(selected !is null && selected !is obj) {
		string@ strAU = localize("#MO_AU");
		float dist = selected.getPosition().getDistanceFrom(obj.getPosition());
		if(dist > 0.01f) {
			mo_text += combine("\n", localize("#MO_Distance"), formatDistance(dist), strAU);
		}

		if (selected.getOwner() is emp && obj.toStar() !is null) {
			HulledObj@ hulled = selected;

			if (hulled !is null && hulled.getHull().hasSystemWithTag(strJumpDrive)) {
				float minRange = -1.f;
				float maxRange = -1.f;

				// Get the jump drive ranges
				uint cnt = hulled.getSubSystemCount();
				for (uint i = 0; i < cnt; ++i) {
					subSystem@ sys = hulled.getSubSystem(i).system;
					if (sys.type.hasTag(strJumpDrive)) {
						float mn = sys.getVariable(strMinRange);
						float mx = sys.getVariable(strMaxRange);

						if (minRange < 0 || mn < minRange)
							minRange = mn;
						if (maxRange < 0 || mx > maxRange)
							maxRange = mx;
					}
				}

				bool inRange = dist > minRange && dist < maxRange;
				mo_text += combine("\n", localize("#MO_JumpRange"),
						inRange ? "#c:00dc00#" : "#c:dc0000#",
						combine(formatDistance(minRange), strAU, " - ",
							    formatDistance(maxRange), strAU),
						"#c#");
			}
		}
	}
		
	if (owner is emp) {
		// Fleet and Orders
		OrderList orders;
		if(orders.prepare(obj)) {
			uint ordCnt = orders.getOrderCount();

			if (hull !is null) {
				Fleet@ fl = hull.getFleet();
				if (fl !is null) {
					if (orders.isFleetCommander())
						mo_text += ("\n" + fl.getName()) + combine(" ",
								localize("#MO_Commander"), "\n  " +
								orders.getFleetSize(), " ",
								localize("#MO_Ships"));
					else
						mo_text += ("\n" + fl.getName());
				}
			}

			for (uint i = 0; i < ordCnt; ++i) {
				Order@ ord = orders.getOrder(i);
				if (!ord.isAutomation()) {
					mo_text += "\n" + orders.getOrder(i).getName();
					break;
				}
			}
		}
	}
	else {
		// Other owner
		HulledObj@ ship = obj;
		if(pl !is null || ship !is null) {
			if(owner !is null) {
				mo_text += "\n";
				mo_text += owner.getName();
				if(emp.isEnemy(owner))
					mo_text += " ("+localize("#MO_Enemy")+")";
				else if(emp.isAllied(owner))
					mo_text += " ("+localize("#MO_Allied")+")";
			}
		}
	}
	
	mouseOverlay.setText(combine("#font:stroked#", mo_text, "#font#"));
}

void hideNearOverlay() {
	if(glowLine.isVisible()) {
		glowLine.setVisible(false);
		nrov_name.setVisible(false);
		nrov_hpTag.setVisible(false);
		nrov_hpBar.setVisible(false);
		nrov_build.setVisible(false);
	}
}

void showNearOverlay() {
	if(!glowLine.isVisible()) {	//Show things that are always visible
		glowLine.setVisible(true);
		nrov_name.setVisible(true);
	}
}

bool rebuildPositions = false;

//Updates the state of the overlay that appears when close to an object
//Returns true if the overlay is visible, false otherwise
bool updateNearbyObject(Object@ obj) {
	recti apparentSize;
	if(getApparentPos(apparentSize)) {
		int width = apparentSize.getWidth();
		if(width > 128) {
			bool wasVisible = glowLine.isVisible();
			showNearOverlay();
			
			Empire@ emp = getActiveEmpire();
			
			float val = 0.f, max = 0.f, req = 0.f, cargo = 0.f;
			obj.getStateVals("Damage", val, max, req, cargo);
			
			pos2di topRight = apparentSize.UpperLeftCorner;
			if(!wasVisible || rebuildPositions ||
				(abs(lastTopRight.x - topRight.x) + abs(lastTopRight.y - topRight.y) > 2)) { //Make sure it's moved at least 3 pixels, to avoid twitching
				rebuildPositions = false;
				lastTopRight = topRight;
				topRight.x += width;
				
				dim2di lineSize = glowLine.getSize();
				pos2di glowTR = topRight + pos2di(lineSize.width / 2, -lineSize.height);
				
				glowLine.setPosition(topRight - pos2di(lineSize.width / 2, lineSize.height));
				nrov_name.setPosition(glowTR - pos2di(118, 15));
				
				uint barOffset = 15;
				
				if(max > 0) {
					nrov_hpTag.setVisible(false); nrov_hpBar.setVisible(false);
				}
				else {
					nrov_hpTag.setVisible(true); nrov_hpBar.setVisible(true);
					nrov_hpTag.setPosition(glowTR + pos2di(-100, barOffset));
					nrov_hpBar.setPosition(glowTR + pos2di(-50, barOffset + 5));
					barOffset += 15;
				}
				
				if(obj.getConstructionQueueSize() == 0 || @obj.getOwner() != @emp) {
					nrov_build.setVisible(false);
					nrov_build.setText(null);
				}
				else {
					nrov_build.setVisible(true);
					nrov_build.setPosition(glowTR + pos2di(-200, barOffset));
					barOffset += 15;
				}
			}
			
			nrov_name.setText("#align:right#" + obj.getName());
			
			if(max > 0) {
				nrov_hpBar.setPct(1.f - (val / max));
				nrov_hpBar.setToolTip(standardize(max - val) + "/" + standardize(max));
			}
			
			uint qSize = obj.getConstructionQueueSize();
			if(qSize == 0) {
				if(nrov_build.isVisible())
					rebuildPositions = true;
			}
			else if(nrov_build.isVisible()) {
				string@ buildName = obj.getConstructionName();
				float buildPct = obj.getConstructionProgress();
				if(@buildName != null) {
					string@ outText = "";
					fitStrToPixels(buildName, 180, outText, null, ": (" + round(buildPct * 100.f) + "%)");
					nrov_build.setText("#align:right##img:obj_building_yes# " + outText);
				}
			}
			else {
				rebuildPositions = true;
			}
		}
		else {
			hideNearOverlay();
		}
	}
	else {
		hideNearOverlay();
	}
	return glowLine.isVisible();
}

void OnMouseOverContext(Object@ obj, pos2di mousePos) {
	// Can't hover while the context menu is up
	if (isContextMenuUp())
		@obj = null;

	GuiElement@ mo_ele = mouseOverlay;
	
	Object@ focus = getCameraFocus();
	
	if (obj is null || !obj.isValid() || (focus is obj && updateNearbyObject(focus))) {
		@curObject = null;
		if(focus is null)
			hideNearOverlay();
		mo_ele.setVisible(false);
	}
	else {		
		mo_ele.setVisible(true);
		mo_ele.bringToFront();
		
		setMouseOverlayText(obj);
		anchorToMouse(mo_ele);
	}
}

int ei_left_margin = 2, ei_margin = 4, ei_top_margin = 2;

int get_ei_top() {
	return ei_top_margin + empMsgBG.getSize().height;
}

GuiElement@ findIndicator(int ID) {
	return getElementByID(ID, empMsgBG);
}

GuiElement@[] eventIndicators;

void showEventIndicator(GuiElement@ ele) {
	ele.setParent(empMsgBG);
	ele.setNoclipped(true);
	
	int left = ei_left_margin, top = ei_top;
	uint ei_count = eventIndicators.length();
	for(uint i = 0; i < ei_count; ++i)
		left += eventIndicators[i].getSize().width + ei_margin;
	
	ele.setPosition( pos2di(left, top) );
	ele.setAlignment(EA_Left, EA_Bottom, EA_Left, EA_Bottom);
	
	eventIndicators.resize(ei_count + 1);
	@eventIndicators[ei_count] = @ele;
}

void hideEventIndicator(GuiElement@ ele) {
	int left = ei_left_margin, top = ei_top;
	uint ei_count = eventIndicators.length();
	
	uint i;
	for(i = 0; i < ei_count; ++i) {
		if(eventIndicators[i] is ele) {
			ele.remove();
			eventIndicators.erase(i);
			ei_count -= 1;
			break;
		}
		left += eventIndicators[i].getSize().width + ei_margin;
	}
	
	for(;i < ei_count; ++i) {
		eventIndicators[i].setPosition( pos2di(left, top) );
		left += eventIndicators[i].getSize().width + ei_margin;
	}
}
