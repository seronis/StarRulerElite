const string@ strOre = "Ore", strDamage = "Damage", strMass = "mass";
const string@ strMtl = "Metals", strMine = "MineM", strMtlGen = "MtlG";
const string@ strElc = "Electronics", strElcGen = "ElcG";
const string@ strAdv = "AdvParts", strAdvGen = "AdvG", strFoodGen = "FudGe";
const string@ strFood = "Food", strGoods = "Guds", strLuxuries = "Luxs";
const string@ strFuel = "Fuel", strFuelGen = "FuelG", strAmmo = "Ammo", strAmmoGen = "AmmoG";
const string@ strLabor = "Labr", strWorkers = "Workers", strTrade = "Trade", strMood = "Mood", strTradeMode = "TradeMode";
const string@ actShortWorkWeek = "work_low", actForcedLabor = "work_forced", actTaxBreak = "tax_break", strEthics = "ethics", strEcoMode = "eco_mode";
const string@ actStockPile = "act_stockpile";
const string@ strRadius = "radius", strStatic = "static";
const string@ strLuxsGen = "LuxG", strGudsGen = "GudsG";

const string@ strNoFood = "no_food", strFastConsumption = "fast_consumption", strConsumeMetals = "consume_metals", strFastReproduction = "fast_reproduction";
const string@ strPlanetClearOnLost = "planet_clear_on_lost", strDisableCivilActs = "disable_civil_acts";
const string@ strAlwaysHappy = "always_happy", strPlanetRemoveConditions = "planet_remove_conditions";
const string@ strLowLuxuries = "low_luxuries_consumption", strHighLuxuries = "high_luxuries_consumption";
const string@ strDoubleLabor = "double_pop_labor", strIndifferent = "forever_indifferent";
const string@ strHalfExports = "half_exports";

const string@ strPosition = "position", strRotation = "rotation";

const double million = 1000000.0;
const double c_e = 2.71828183;

import float processOre(Object@ obj, float Rate) from "Economy";
import float makeElectronics(Object@ obj, float Rate) from "Economy";
import float makeAdvParts(Object@ obj, float Rate) from "Economy";
//import float makeFuel(Object@ obj, float Rate) from "Economy";
//import float makeAmmo(Object@ obj, float Rate) from "Economy";

//EMPIRE ACTS:
//============
//Short Work Week:
//	75% labor output, happiness trends toward 25%
//Forced Labor:
//	80% labor output, regardless of happiness; happiness trends toward -50%

//Work Ethic Campaign:
//	150% labor output, 75% economic output
//Academic Campaign:
//	50% labor output, 125% economic output

//Tax Break:
//	People consume goods 50% faster (more happiness as a result, but low supply causes problems faster)
//Regressive Tax:
//	Goods consumption reduced 50%. Metals Production reduced 50%, Electronics reduced 20%. Mood -10%.
//Progressive Tax:
//	Luxuries consumption reduced 50%. Electronics Production reduced 20%, AdvParts reduced 50%. Mood -20%.

//RESOURCE MODES:
//Metal/Electronics/AdvParts Focus
// +50% Chosen resource generation rate. -35% Other resource generation rate
//Metal/Electronics/AdvParts Frenzy
// +100% Chosen resource generation rate. -90% Other resource generation rate

const float baseWorkRate = 0.5f, workPopulationLevel = float(60.0 * million), workMoodImpact = 2.f, laborRate = 10.f;

const float moodDecayRate = float(1.0 - 0.1);

const float goodsPerPerson = float(15.0 / million), luxPerPerson = float(1.5 / million);
const float noGoodsDecay = float(1.0 - 0.1), luxGrowth = float(1.0 - 0.135);

float approachVal(float val, float approach, float percentToward) {
	return approach + ((val - approach) * percentToward);
}


enum popMode {
	PM_Normal,
	PM_Work_Slow,
	PM_Work_Hard
};

enum ethic {
	EC_Normal,
	EC_Labor,
	EC_Economy,
};

enum ecoMode {
	EM_Normal,
	EM_Focus,
	EM_Frenzy,
	
	EM_Metals,
	EM_Elects,
	EM_AdvParts,
};

enum TradeMode {
	TM_All,
	TM_ImportOnly,
	TM_ExportOnly,
	TM_Nothing,
};

void popEcoInit(Event@ evt) {
	State@ mood = evt.obj.getState(strMood);
	mood.max = 1.f;
	evt.obj.getState(strLuxsGen);
	evt.obj.getState(strGudsGen);
	evt.obj.getState(strFoodGen);
	evt.obj.getState(strTrade);
	evt.obj.getState(strFoodGen);
	evt.obj.getState(strFood);
	evt.obj.getState(strMtl);
	evt.obj.getState(strMine);
	evt.obj.getState(strMtlGen);
	evt.obj.getState(strElc);
	evt.obj.getState(strElcGen);
	evt.obj.getState(strAdv);
	evt.obj.getState(strAdvGen);
	evt.obj.getState(strFuel);
	evt.obj.getState(strFuelGen);
	evt.obj.getState(strAmmo);
	evt.obj.getState(strAmmoGen);
}

float modifyEcoRate(float rate, ecoMode type, ecoMode rateMode, ecoMode typeMode) {
	if(rateMode == EM_Normal)
		return rate;
	if(type == typeMode) {
		if(rateMode == EM_Focus)
			return rate * 1.5f;
		else
			return rate * 2.f;
	}
	else {
		if(rateMode == EM_Focus)
			return rate * 0.65f; //-35%
		else
			return rate * 0.1f; //-90%
	}
}

//Performs economic generation for planets
void tick(Planet@ pl, float time) {
	Object@ obj = pl;
	Empire@ emp = obj.getOwner();
	if(emp is null || emp.isValid() == false)
		return;
	
	State@ mood = obj.getState(strMood);
	
	float population = pl.getPopulation();
	if(population <= 0.1f)
		return;
	
	float lackOfWorkers = 1.f;
	{
		State@ workers = pl.toObject().getState(strWorkers);
		lackOfWorkers = clamp(workers.val / max(workers.required,1.f),0.1f,1.f);
	}

	// Update population growth
	float foodSupplyPct = 1.f;
	{
		float pop = pl.getPopulation();
		float maxPop = pl.getMaxPopulation();
		float reproduction = 0.02f;
		float consumptionRate = 1.f;

		if (emp.hasTraitTag(strFastConsumption))
			consumptionRate *= 2.f;
		if (emp.hasTraitTag(strFastReproduction))
			reproduction *= 2.f;
		if(obj.isUnderAttack())
			reproduction *= 0.5f;

		float growth = (pop * maxPop) / (pop + ((maxPop - pop) * pow(float(c_e), -reproduction * time))) - pop;
		pl.modPopulation(growth);

		// Consume food
		if (!emp.hasTraitTag(strNoFood)) {
			// Consume food
			double consumption = 0.06/million * double(consumptionRate);
			foodSupplyPct = populationConsume(pl, strFood, consumption, time);
		}

		// Consume metals if we have that trait
		if (emp.hasTraitTag(strConsumeMetals)) {
			double consumption = 6/million * double(consumptionRate);
			foodSupplyPct = populationConsume(pl, strMtl, consumption, time);
		}
	}
	
	bool hasCivilActs = !emp.hasTraitTag(strDisableCivilActs);
	popMode mode = PM_Normal;
	if (hasCivilActs)
		if(emp.getSetting(actShortWorkWeek) == 1)
			mode = PM_Work_Slow;
		else if(emp.getSetting(actForcedLabor) == 1)
			mode = PM_Work_Hard;
	
	ethic workEthic = EC_Normal;
	if (hasCivilActs)
		switch(uint(emp.getSetting(strEthics))) {
			case 1:
				workEthic = EC_Labor; break;
			case 2:
				workEthic = EC_Economy; break;
		}
	
	ecoMode ecoRate = EM_Normal, ecoType = EM_Metals;
	uint ecoSetting = 0;

	if (hasCivilActs) {
		ecoSetting = uint(emp.getSetting(strEcoMode));
		switch((ecoSetting-1) % 3) { //pick 1-3 and 4-6 as 0-2
			case 0:
				ecoType = EM_Metals; break;
			case 1:
				ecoType = EM_Elects; break;
			case 2:
				ecoType = EM_AdvParts; break;
		}
	}
	
	if(ecoSetting >= 4)
		ecoRate = EM_Frenzy;
	else if(ecoSetting > 0)
		ecoRate = EM_Focus;
	
	float moodDecayFactor = time;
	float moodDecayToward = 0;
	bool hasMood = !emp.hasTraitTag(strIndifferent);
	
	float workRate = time * baseWorkRate * lackOfWorkers * (0.5f + (population / workPopulationLevel));
	switch(mode) {
		case PM_Work_Slow:
			workRate *= 0.75f;
			moodDecayToward = 0.25f;
		case PM_Normal:
			workRate *= pow(workMoodImpact, mood.val);
			break;
		case PM_Work_Hard:
			workRate *= 0.8f;
			moodDecayToward = -0.5f;
			break;
	}
	
	//Decay mood
	if (hasMood)
		mood.val = approachVal(mood.val, moodDecayToward, pow(moodDecayRate,moodDecayFactor));
	else
		mood.val = 0;
	
	float tickLabor = workRate * laborRate;
	float tickEco = workRate;
	if(workEthic == EC_Labor) {
		tickLabor *= 1.5f;
		tickEco *= 0.9f;
	}
	else if(workEthic == EC_Economy) {
		tickLabor *= 0.5f;
		tickEco *= 1.1f;
	}

	if (emp.hasTraitTag(strDoubleLabor))
		tickLabor *= 2.f;

	//Produce things
	State@ labor = obj.getState(strLabor);
	obj.getState(strLabor).add(tickLabor, obj);	

	State@ foodRate = obj.getState(strFoodGen);
	State@ goodsRate = obj.getState(strGudsGen);
	State@ luxsRate = obj.getState(strLuxsGen);

	goodsRate.inCargo = 0;
	luxsRate.inCargo = 0;

	float produceGoods = goodsRate.max * time;
	float produceLuxs = luxsRate.max * time;

	System@ parent = obj.getParent();
	bool blockaded = parent !is null && parent.isBlockadedFor(emp);
	
	State@ advRate = obj.getState(strAdvGen);
	if(@advRate != null && advRate.max > 0)
		advRate.val = makeAdvParts(obj, modifyEcoRate(advRate.max * tickEco, EM_AdvParts, ecoRate, ecoType)) / time;
		
	State@ elcRate = obj.getState(strElcGen);
	if(@elcRate != null && elcRate.max > 0)
		elcRate.val = makeElectronics(obj, modifyEcoRate(elcRate.max * tickEco, EM_Elects, ecoRate, ecoType)) / time;
	
	State@ mtlRate = obj.getState(strMine);
	if(@mtlRate != null && mtlRate.max > 0)
		mtlRate.val = processOre(obj, modifyEcoRate(mtlRate.max * tickEco, EM_Metals, ecoRate, ecoType)) / time;
		
	State@ fuelRate = obj.getState(strFuelGen);
		/*
	if(@fuelRate != null && fuelRate.max > 0)
		fuelRate.val = makeFuel(obj, fuelRate.max) / time;
		*/
		
	State@ ammoRate = obj.getState(strAmmoGen);
		/*
	if(@ammoRate != null && ammoRate.max > 0)
		ammoRate.val = makeAmmo(obj, ammoRate.max * tickEco) / time;
		*/
		
	float consumeFactor = time;
	if(hasCivilActs && emp.getSetting(actTaxBreak) == 1)
		consumeFactor *= 1.5f;
	
	if(hasMood) {
		//Consume goods and luxuries
		//Lacking goods only hurts happiness
		const float needGoods = population * goodsPerPerson * consumeFactor;
		float gotGoods = 0.f;
		if (produceGoods > 0) {
			if (needGoods < produceGoods) {
				produceGoods -= needGoods;
				gotGoods += needGoods;
			}
			else {
				gotGoods += produceGoods;
				produceGoods = 0.f;
			}
		}

		if (!blockaded) {
			float consumedGoods = emp.consumeStat(strGoods, needGoods - gotGoods);
			gotGoods += consumedGoods;
			goodsRate.inCargo = consumedGoods;
		}

		if(gotGoods < needGoods)
			mood.val = approachVal(mood.val, -1.f, pow(noGoodsDecay, consumeFactor * (needGoods-gotGoods)/needGoods) );
	
		//Having luxuries only increases happiness
		float needLux = population * luxPerPerson * consumeFactor;
		if (emp.hasTraitTag(strLowLuxuries))
			needLux *= 0.5f;
		else if (emp.hasTraitTag(strHighLuxuries))
			needLux *= 2.f;

		float gotLux = 0.f;
		if (produceLuxs > 0) {
			if (needLux < produceLuxs) {
				produceLuxs -= needLux;
				gotLux += needLux;
			}
			else {
				gotLux += produceLuxs;
				produceLuxs = 0.f;
			}
		}

		luxsRate.inCargo = gotLux;
		if (!blockaded) {
			float consumedLux = emp.consumeStat(strLuxuries, needLux - gotLux);
			gotLux += consumedLux;
			luxsRate.inCargo = consumedLux;
		}

		if(gotLux > 0)
			mood.val = approachVal(mood.val, 1.f, pow(luxGrowth, consumeFactor * (1.f - (needLux-gotLux)/needLux) ) );
		
		if(pl.toObject().isUnderAttack())
			mood.val = approachVal(mood.val, -1.f, pow(noGoodsDecay, time));
		if(foodSupplyPct < 1.f)
			mood.val = approachVal(mood.val, -1.f + foodSupplyPct, pow(noGoodsDecay, time));

		//Artificially keep population happy
		if (mood.val < 0 && emp.hasTraitTag(strAlwaysHappy))
			mood.val = 0;
	}

	// Add excess goods/luxuries to the bank
	if (!blockaded) {
		if (produceGoods > 0) {
			emp.addStat(strGoods, produceGoods);
			goodsRate.inCargo -= produceGoods;
		}
		goodsRate.inCargo /= time;

		if (produceLuxs > 0) {
			emp.addStat(strLuxuries, produceLuxs);
			luxsRate.inCargo -= produceLuxs;
		}
		luxsRate.inCargo /= time;

		//Trade things
		State@ tradeRate = obj.getState(strTrade);
		float tickTrade = tradeRate.val * time * lackOfWorkers;
		float tradeTarget = 0.5f;

		if (hasCivilActs && emp.getSetting(actStockPile) >= 0.5f)
			tradeTarget = 0.95f;

		if(tickTrade > 0.f) {
			float tradeEff = 1.f;
			if (gameTime < 1200.f && emp.hasTraitTag(strHalfExports))
				tradeEff = 0.5f;

			float cargoUsed, cargoSpace, cargoSpaceLeft;
			obj.getCargoVals(cargoUsed, cargoSpace); cargoSpaceLeft = cargoSpace - cargoUsed;
		
			// Figure out trade mode
			float tval = 0, tmax = 0, treq = 0, tcargo = 0;
			TradeMode advMode = TM_All, elcMode = TM_All, mtlMode = TM_All, fudMode = TM_All;
			if (obj.getStateVals(strTradeMode, tval, tmax, treq, tcargo)) {
				advMode = TradeMode(int(tval));
				elcMode = TradeMode(int(tmax));
				mtlMode = TradeMode(int(treq));
				fudMode = TradeMode(int(tcargo));
			}
			
			//emp.getStatStats(strFood, v,i,e,d);	
			State@ sp_Food = obj.getState(strFood);
			float foodWeight = getResourceWeight(sp_Food, cargoSpaceLeft, tradeTarget); //float(e/max(i,1.0));
			
			State@ sp_Metals = obj.getState(strMtl);
			float mtlWeight = getResourceWeight(sp_Metals, cargoSpaceLeft, tradeTarget);
			
			State@ sp_Elecs = obj.getState(strElc);
			float elecWeight = getResourceWeight(sp_Elecs, cargoSpaceLeft, tradeTarget);
			
			State@ sp_Advs = obj.getState(strAdv);
			float advWeight = getResourceWeight(sp_Advs, cargoSpaceLeft, tradeTarget);
			
			State@ sp_Fuel = obj.getState(strFuel);
			float fuelWeight = getResourceWeight(sp_Fuel, sp_Fuel.getTotalFreeSpace(obj), tradeTarget);
			
			State@ sp_Ammo = obj.getState(strAmmo);
			float ammoWeight = getResourceWeight(sp_Ammo, sp_Ammo.getTotalFreeSpace(obj), tradeTarget);
			
			float totalWeight = abs(foodWeight) + abs(mtlWeight) + abs(elecWeight) + abs(advWeight) + abs(fuelWeight) + abs(ammoWeight);
			
			if(totalWeight > 0) {
				advRate.inCargo  = tradeResource(emp, obj, sp_Advs,   strAdv,  tickTrade *  advWeight/totalWeight, tradeEff, advMode);
				elcRate.inCargo  = tradeResource(emp, obj, sp_Elecs,  strElc,  tickTrade * elecWeight/totalWeight, tradeEff, elcMode);
				mtlRate.inCargo  = tradeResource(emp, obj, sp_Metals, strMtl,  tickTrade *  mtlWeight/totalWeight, tradeEff, mtlMode);
				foodRate.inCargo = tradeResource(emp, obj, sp_Food,   strFood, tickTrade * foodWeight/totalWeight, 1.f,      fudMode);
				fuelRate.inCargo = tradeResource(emp, obj, sp_Fuel,   strFuel, tickTrade * fuelWeight/totalWeight, tradeEff, fudMode);
				ammoRate.inCargo = tradeResource(emp, obj, sp_Ammo,   strAmmo, tickTrade * ammoWeight/totalWeight, tradeEff, mtlMode);
				tickTrade -= abs(advRate.inCargo)  + abs(elcRate.inCargo)  + abs(mtlRate.inCargo)
				           + abs(foodRate.inCargo) + abs(fuelRate.inCargo) + abs(ammoRate.inCargo);
			}
			else {
				advRate.inCargo  = 0;
				elcRate.inCargo  = 0;
				mtlRate.inCargo  = 0;
				foodRate.inCargo = 0;
				fuelRate.inCargo = 0;
				ammoRate.inCargo = 0;
			}
			
			float traded = 0.f;

			if (tickTrade > 0) {
				traded = tradeResource(emp, obj, sp_Food, strFood, tickTrade * sign(foodWeight), 1.f,      fudMode);
				foodRate.inCargo += traded;
				tickTrade -= abs(traded);
			}

			if(tickTrade > 0) {
				traded = tradeResource(emp, obj, sp_Advs, strAdv, tickTrade * sign(advWeight), tradeEff, advMode);
				advRate.inCargo += traded;
				tickTrade -= abs(traded);
			}

			if (tickTrade > 0) {
				traded = tradeResource(emp, obj, sp_Elecs, strElc, tickTrade * sign(elecWeight), tradeEff, elcMode);
				elcRate.inCargo += traded;
				tickTrade -= abs(traded);
			}

			if (tickTrade > 0) {
				traded = tradeResource(emp, obj, sp_Metals, strMtl, tickTrade * sign(mtlWeight), tradeEff, mtlMode);
				mtlRate.inCargo += traded;
				tickTrade -= abs(traded);
			}

			if (tickTrade > 0) {
				traded = tradeResource(emp, obj, sp_Fuel, strFuel, tickTrade * sign(fuelWeight), tradeEff, fudMode);
				fuelRate.inCargo += traded;
				tickTrade -= abs(traded);
			}

			if(tickTrade > 0) {
				traded = tradeResource(emp, obj, sp_Ammo, strAmmo, tickTrade * sign(ammoWeight), tradeEff, mtlMode);
				ammoRate.inCargo += traded;
				tickTrade -= abs(traded);
			}
			tradeRate.required = ((tradeRate.val * time) - tickTrade) / time;

			advRate.inCargo  /= time;
			elcRate.inCargo  /= time;
			mtlRate.inCargo  /= time;
			foodRate.inCargo /= time;
			fuelRate.inCargo /= time;
			ammoRate.inCargo /= time;
		}
		else {
			advRate.inCargo  = 0;
			elcRate.inCargo  = 0;
			mtlRate.inCargo  = 0;
			foodRate.inCargo = 0;
			fuelRate.inCargo = 0;
			ammoRate.inCargo = 0;

			tradeRate.required = 0;
		}
	}
	else {
		advRate.inCargo   = 0;
		elcRate.inCargo   = 0;
		mtlRate.inCargo   = 0;
		foodRate.inCargo  = 0;
		goodsRate.inCargo = 0;
		luxsRate.inCargo  = 0;
		fuelRate.inCargo  = 0;
		ammoRate.inCargo  = 0;

		State@ tradeRate = obj.getState(strTrade);
		tradeRate.required = 0;
	}

	// Update worker stat
	State@ workers = pl.toObject().getState(strWorkers);
	workers.val = pl.getPopulation();
	workers.max = pl.getMaxPopulation();
}

float sign(float x) {
	if(x > 0)
		return 1.f;
	else if(x < 0)
		return -1.f;
	else
		return 0.f;
}

float getResourceWeight(State@ state, float freeCargoSpace, float tradeToPct) {
	if(abs(state.max) < 0.01f)
		return 0.f;
	float pct = (state.val + state.inCargo)	/ (state.max + state.inCargo + freeCargoSpace);
	if(pct > 0.5f)
		return (1.f/tradeToPct) * (pct - tradeToPct);
	else if(pct < 0.5f)
		return (-1.f/tradeToPct) * (tradeToPct - pct);
	else
		return 0;
}

//Trade a maximal amount of the specified resource. If amount is negative, it will be imported.
//Returns the amount that was traded
float tradeResource(Empire@ emp, Object@ obj, State@ state, const string@ statName, float amount, float tradeEff, TradeMode mode) {
	if (mode == TM_Nothing)
		return 0;
	if(abs(amount) < 0.01f)
		return 0;
	float cargoUsed, cargoMax;
	obj.getCargoVals(cargoUsed, cargoMax);
	
	float halfCapacity = (state.max + cargoMax + state.inCargo - cargoUsed) * 0.5f;
	if(amount > 0) {
		if (mode == TM_ImportOnly)
			return 0;
		float give = min(state.val + state.inCargo - halfCapacity, amount);
		if(give > 0.05f) {
			emp.addStat(statName, give * tradeEff);
			state.consume(give, obj);
			return give;
		}
		else {
			return 0;
		}
	}
	else {
		if (mode == TM_ExportOnly)
			return 0;
		amount = abs(amount);
		float take = min(halfCapacity - (state.val + state.inCargo), amount);
		if(take > 0.05f) {
			take = emp.consumeStat(statName, take);
			if(take > 0) {
				state.add(take, obj);
				return -take;
			}
			else {
				return 0;
			}
		}
		else {
			return 0;
		}
	}
	
}

/* Helper to consume an amount of resource per population */
//Returns the pct of food we ate compared to our needs
float populationConsume(Planet@ pl, const string@ state, double amnPer, double time) {
	double pop = pl.getPopulation();
	double maxPop = pl.getMaxPopulation();

	State@ res = pl.toObject().getState(state);
	double avail = res.getAvailable();
	double needed = pop * time * amnPer;

	if (avail >= needed) {
		res.consume(needed, pl.toObject());
		return 1.f;
	}
	else {
		res.consume(avail, pl.toObject());
		//Up to 10% of the population will die per second
		pl.modPopulation(-1.f * min((needed - avail) / amnPer, pop * (1.f - pow(0.9f,float(time))) ));
		return avail/needed;
	}
}

// Is called when a planet is destroyed. Return true to prevent the destruction.
bool onDestroy(Planet@ pl, bool silent) {
	if (!silent) {
		System@ sys = pl.toObject().getParent();
		if (sys is null)
			return false;

		State@ ore = pl.toObject().getState(strOre);

		// A percentage of max ore is base
		float remnOre = ore.max * 0.1f;

		// All the ore left on the planet
		remnOre += ore.getAvailable();

		// All the metals left on the planet
		remnOre += pl.toObject().getState(strMtl).getAvailable();

		// Make asteroids
		Oddity_Desc asteroid_desc;
		asteroid_desc.id = "asteroid";

		vector pos = pl.toObject().position;
		float dist = 90.f;

		uint rocks = rand(1, 10);
		for (uint i = 0; i < rocks; ++i) {
			float orePerc = randomf(0.9f, 1.1f) / rocks;
			float useOre = orePerc * remnOre;

			asteroid_desc.clear();
			asteroid_desc.setFloat(strRadius, orePerc * randomf(15.f, 30.f));
			asteroid_desc.setFloat(strStatic, 1.f);
			asteroid_desc.setFloat(strMass, useOre);

			asteroid_desc.setVector(strPosition, pos + vector(randomf(-0.5f, 0.5f) * dist, randomf(-0.5f, 0.5f) * dist, randomf(-0.5f, 0.5f) * dist));
			asteroid_desc.setVector(strRotation, vector(randomf(360.f), randomf(360.f), randomf(360.f)));

			Object@ asteroid = sys.makeOddity(asteroid_desc);
		
			State@ ore = asteroid.getState(strOre);
			ore.max = useOre;
			ore.val = ore.max;

			State@ dmg = asteroid.getState(strDamage);
			dmg.max = useOre;
			dmg.val = 0;
		}

		if(canAchieve)
			achieve(AID_DEST_PLANET);
	}

	return false;
}

// Is called when a planet changes owners. Return true to prevent the takeover.
bool onOwnerChange(Planet@ pl, Empire@ from, Empire@ to) {
	Object@ obj = pl;

	// Clear planet when previous owner has trait
	if (from !is null && from.isValid() && from.hasTraitTag(strPlanetClearOnLost)) {
		obj.clearBuildQueue();
		pl.removeAllStructures();
	}

	// Remove planet conditions if new owner has trait
	if (to !is null && to.isValid() && to.hasTraitTag(strPlanetRemoveConditions)) {
		for (int i = pl.getConditionCount() - 1; i >= 0; --i) {
			const PlanetCondition@ cond = pl.getCondition(i);
			if (!cond.constructed)
				pl.removeCondition(cond.get_id());
		}
	}

	// Check achievements
	if (canAchieve && to is getPlayerEmpire()) {
		if(pl.hasCondition("microcline")) {
			achieve(AID_MICROCLINE);
		}
	}

	// Clear any import/export flags
	float tmp = 0;
	if (obj.getStateVals(strTradeMode, tmp, tmp, tmp, tmp))
		obj.setStateVals(strTradeMode, 0, 0, 0, 0);

	return false;
}

// Is called when a planet is repaired. Return true to prevent normal repair behaviour.
// bool onRepair(Planet@ pl, float amount) {
// 	return false;
// }

string@ strDR = "DR";
// Is called when a planet is damaged. Return true to prevent normal damage behaviour.
bool onDamage(Planet@ pl, Event@ evt) {
	State@ dr = pl.toObject().getState(strDR);
	if(dr !is null)
		evt.damage *= 1 - (dr.max / (1500 + dr.max));
 	return false;
}

// Prototype for a build queue script call
// Return true to prevent the rest of the queue from executing
// build_queues.xml will need an <script call="module::function" /> entry to use the function.
//
// bool onQueueEvent(Planet@ pl) {
// 	return false;
// }
