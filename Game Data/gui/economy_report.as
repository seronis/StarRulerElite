
import recti makeScreenCenteredRect(const dim2di &in rectSize) from "gui_lib";

GuiDraggable@ window;

//#GBR_advparts: Advanced Parts
//#GBR_electronics: Electronics
//#GBR_metals: Metals
//#GBR_luxuries: Luxuries
//#GBR_goods: Goods
//#GBR_food: Food

string@[] cols =       { "#advparts",    "#electronics", "#metals",      "#food",
                         "#goods",       "#luxuries",    "#fuel",        "#ammo"      };
string@[] stats =      { "AdvParts",     "Electronics",  "Metals",       "Food",
                         "Guds",         "Luxs",         "Fuel",         "Ammo"       };
uint[] headingColors = {  0xffc2e4ff,     0xfff6ff00,     0xffeaeaea,     0xff197b30,
                          0xff987433,     0xffffb9b9,     0xffff8000,     0xffaaaaaa  };
GuiStaticText@[] elements(8*5,null);

void OpenEconomyReport() {
	window.setVisible(true);
	window.bringToFront();
	bindEscapeEvent(window);
}

void ToggleEconomyReport() {
	if (window.isVisible()) {
		window.setVisible(false);
		clearEscapeEvent(window);
	}
	else {
		window.setVisible(true);
		window.bringToFront();
		bindEscapeEvent(window);
	}
}

void init() {
	@window = GuiDraggable(getSkinnable("Dialog"), makeScreenCenteredRect(dim2di(652,138)), true, null);
	window.setVisible(false);

	GuiButton@ closeButton = GuiButton(recti(pos2di(window.getSize().width-30,0), dim2di(30,12)), null, window);
	closeButton.setImage("planet_close");
	closeButton.orphan(true);

	bindGuiCallback(closeButton, "OnWinClose");
	bindGuiCallback(window, "OnWinClose");
	
	GuiStaticText@ txt;
	
	//Columns
	for(uint i = 0; i < cols.length(); ++i) {
		@txt = GuiStaticText(recti(pos2di(76 + (i * 70), 21), dim2di(70,15)), localize(cols[i]), false, false, false, window);
		txt.setTextAlignment(EA_Right, EA_Top);
		txt.setColor(Color(headingColors[i]));
		txt.orphan(true);
		
		for(uint h = 0; h < 5; ++h) {
			int offset = h > 1 ? 10 : 0;
			@txt = GuiStaticText(recti(pos2di(76 + (i * 70), 38 + (16 * h) + offset), dim2di(70,15)), "0", false, false, false, window);
			txt.setTextAlignment(EA_Right, EA_Top);
			txt.orphan(true);
			@elements[(i*5)+h] = @txt;
		}
	}
	
	//Rows
	@txt = GuiStaticText(recti(pos2di(12, 38), dim2di(70,15)), localize("#ER_Stored"), false, false, false, window); txt.orphan(true);
	@txt = GuiStaticText(recti(pos2di(12, 54), dim2di(70,15)), localize("#ER_Net"), false, false, false, window); txt.orphan(true);
	@txt = GuiStaticText(recti(pos2di(12, 80), dim2di(70,15)), localize("#ER_Income"), false, false, false, window); txt.orphan(true);
	@txt = GuiStaticText(recti(pos2di(12, 96), dim2di(70,15)), localize("#ER_Expenses"), false, false, false, window); txt.orphan(true);
	@txt = GuiStaticText(recti(pos2di(12, 112), dim2di(70,15)), localize("#ER_Demand"), false, false, false, window); txt.orphan(true);
}

bool OnWinClose(const GUIEvent@ evt) {
	if(evt.EventType == GEVT_Clicked || evt.EventType == GEVT_Closed) {
		window.setVisible(false);
		return true;
	}
	return false;
}

float nextUpdate = 0;
void tick(float time) {
	nextUpdate += time;
	
	if(window.isVisible() == false)
		return;
	if(nextUpdate < 1)
		return;
	nextUpdate = 0;
	
	Empire@ emp = getActiveEmpire();
	for(uint i = 0; i < cols.length(); ++i) {
		double[] vars(5);
		emp.getStatStats(stats[i], vars[0], vars[2], vars[3], vars[4]);
		vars[1] = vars[2]-vars[3]-vars[4];

		for(uint h = 0; h < 5; ++h) {
			GuiStaticText@ element = elements[(i*5)+h];
			float value = float(vars[h]);

			if (abs(value) < 0.001f) {
				element.setText(standardize(value));
				element.setColor(Color(255, 180, 180, 180));
			}
			else {
				if (h == 1) {
					if (value < 0) {
						element.setText("-"+standardize(abs(value)));
						element.setColor(Color(255, 255, 0, 0));
					}
					else {
						element.setText("+"+standardize(value));
						element.setColor(Color(255, 0, 255, 0));
					}
				}
				else if (h == 2) {
					element.setText("+"+standardize(value));
					element.setColor(Color(255, 0, 255, 0));
				}
				else if (h == 3) {
					element.setText("-"+standardize(value));
					element.setColor(Color(255, 255, 0, 0));
				}
				else if (h == 4) {
					element.setText(standardize(value));
					element.setColor(Color(255, 255, 0, 0));
				}
				else {
					element.setText(standardize(value));
					element.setColor(Color(255, 255, 255, 255));
				}
			}
		}
	}
}
