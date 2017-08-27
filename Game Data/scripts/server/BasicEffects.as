string@ strPower = "Power", strDamage = "Damage", strShields = "Shields";
string@ strControl = "Control", strCrew = "Crew", strWorkers = "Workers";

const string@ strAdvp = "AdvParts";
const string@ strElec = "Electronics";
const string@ strMetl = "Metals";
const string@ strOres = "Ore";
const string@ strScrp = "Scrap";
const string@ strFood = "Food";
const string@ strFuel = "Fuel";
const string@ strAmmo = "Ammo";
const string@ strGuds = "Guds";
const string@ strLuxs = "Luxs";

//Returns the chace of an event occuring within time t
//p should be the chance of the event occuring given t=1
float chanceOverTime(float p, float t) {
	return 1.f-pow(1.f-p,t);
}

void DestructOnPowerOff(Event@ evt) {
	State@ pow = evt.target.getState(strPower);
	if(pow.val <= 0 && evt.obj.toHulledObj() !is null)
		evt.obj.toHulledObj().damageSystem(evt.dest, evt.obj, evt.dest.HP * 2.f);
}

//Like shields, charging capacitors goes slower the closer to full they get
void PowerGen(Event@ evt, float Rate, float Cost) {
	State@ fuel = evt.obj.getState(strFuel), pow = evt.target.getState(strPower);
	float pct = pow.val/pow.max;
	Rate *= 2 * (1 - (pct*pct));
	Rate = min(pow.max - pow.val, Rate * evt.time);
	if(Rate > 0) {
		float p = fuel.getAvailable();
		float use = Rate * Cost;
		if(use <= p) {
			pow.val += Rate;
			fuel.consume(use, evt.obj);
		}
		else {
			pow.val += p / Cost;
			fuel.consume(p, evt.obj);
		}
	}
	
}

void SolarPower(Event@ evt, float Rate, float SurfaceArea) {
	Object@ obj = evt.obj;

	System@ system = obj.getCurrentSystem();
	if(@system == null)
		return;

	State@ power = evt.obj.getState(strPower);
	float canStore = power.getFreeSpace();
	if(canStore <= 0)
		return;

	power.val += min(Rate * evt.time * SurfaceArea * 25000.f / min(obj.position.getLengthSQ(), 50.f*50.f), canStore);
}

void SpeedIfFuel(Event@ evt, float Amount, float Efficiency) {
	State@ fuel = evt.obj.getState(strFuel);

	// Check if we have enough fuel
	if (fuel.getAvailable() <= evt.time * Amount * Efficiency) {
		evt.state = ESC_DISABLE;
		return;
	}

	// Add thrust
	HulledObj@ obj = evt.obj;
	if (obj !is null) {
		obj.thrust = obj.thrust + Amount;
	}
}

void SpeedIfFuel(Event@ evt, float Amount, float Efficiency, float PowCost) {
	State@ power = evt.obj.getState(strPower);
	if (power.getAvailable() <= evt.time * PowCost) {
		evt.state = ESC_DISABLE;
		return;
	}

	SpeedIfFuel(evt, Amount, Efficiency);
}

void FuelThrustCons(Event@ evt, float Amount, float Efficiency) {
	Object@ obj = evt.obj;
	if(obj.velocity.getLengthSQ() > 0.f && obj.inOrbitAround() is null) {
		State@ fuel = obj.getState(strFuel);
		float consume = evt.time * Amount * Efficiency;
		if(fuel.getAvailable() >= consume) {
			fuel.consume(consume,obj);
		}
		else {
			fuel.val = 0;
			evt.state = ESC_DISABLE;
		}
	}
}


void IonThrustCons(Event@ evt, float Amount, float Efficiency, float PowCost) {
	Object@ obj = evt.obj;
	if(obj.velocity.getLengthSQ() > 0.f && obj.inOrbitAround() is null) {
		State@ fuel = obj.getState(strFuel), pow = obj.getState(strPower);
		float consume = evt.time * Amount * Efficiency;
		if(fuel.getAvailable() >= consume) {
			PowCost *= evt.time;
			if(pow.getAvailable() >= PowCost) {
				fuel.consume(consume,obj);
				pow.consume(PowCost,obj);
			}
			else {
				evt.state = ESC_DISABLE;
			}
		}
		else {
			evt.state = ESC_DISABLE;
		}
	}
}

//Delay, in seconds, before the colonizer can colonize again
const float colonizerReloadDelay = 25.f;
//Amount of population given per structure created
const float populationFactor = 1000000.f;

void StandardTakeover(Planet@ plt, Empire@ owner, float makeStructures) {
	plt.Conquer(owner);	
	const subSystemDef@ advpts = getSubSystemDefByName("AdvPartFact"), farm = getSubSystemDefByName("Farm");
	const subSystemDef@ metals = getSubSystemDefByName("MetalMine"), elects = getSubSystemDefByName("ElectronicFact");
	const subSystemDef@ city = getSubSystemDefByName("City"), capital = getSubSystemDefByName("Capital");
	const subSystemDef@ port = getSubSystemDefByName("SpacePort");

	if (owner.hasTraitTag("no_food"))
		if (owner.hasTraitTag("consume_metals"))
			@farm = metals;
		else
			@farm = port;
	if (owner.hasTraitTag("no_bank"))
		@port = farm;

	int makeStructs = min(makeStructures, plt.getMaxStructureCount() - plt.getStructureCount());
	if(plt.getStructureCount(capital) == 0) {
		plt.addStructure(capital);
		makeStructs -= 1;
	}

	makeStructs = clamp(makeStructs, 0, 13);
	switch(makeStructs) {
		case 13:
			plt.addStructure(metals);
		case 12:
			plt.addStructure(advpts);
		case 11:
			plt.addStructure(elects);
		case 10:
			plt.addStructure(city);
		case 9:
			plt.addStructure(farm);
		case 8:
			plt.addStructure(metals);
		case 7:
			plt.addStructure(advpts);
		case 6:
			plt.addStructure(city);
		case 5:
			plt.addStructure(elects);
		case 4:
			plt.addStructure(metals);
		case 3:
			plt.addStructure(farm);
		case 2:
			plt.addStructure(city);
		case 1:
			plt.addStructure(port);
		case 0:
			break;
	}

	//Set the population to the starting pop (correcting any errors in the existing population)
	plt.modPopulation(populationFactor * makeStructures - plt.getPopulation());

	int governorType = floor(owner.getSetting("defaultGovernor"));
	if(owner.getSetting("autoGovern") != 0.f) {
		plt.setUseGovernor(true);
		if(governorType < 0)
			chooseGovernor(plt);
		else if(governorType > 0)
			plt.setGovernorType(owner.getBuildList(governorType-1));
		else
			plt.setGovernorType("default");
	}
	else {
		plt.setGovernorType("default");
		plt.setUseGovernor(false);
	}
}

//Chooses a nearly-optimal governor based on conditions
void chooseGovernor(Planet@ pl) {
	//Heavily prefer economic development in the early game
	if(gameTime < 10.0 * 60.0) {
		if(pl.hasCondition("geotherm"))
			pl.setGovernorType("economic");
		if(pl.hasCondition("ore_rich") && !pl.hasCondition("ore_poor"))
			pl.setGovernorType("metalworld");
		else {
			if(randomf(1.f) < 0.5f)
				pl.setGovernorType("economic");
			else
				pl.setGovernorType("default");
		}
	}
	else {
		if(pl.hasCondition("ore_rich") && !pl.hasCondition("ore_poor"))
			pl.setGovernorType("metalworld");
		else if(pl.hasCondition("geotherm")) {
			if(randomf(1.f) < 0.5f)
				pl.setGovernorType("advpartworld");
			else
				pl.setGovernorType("elecworld");
		}
		else if(pl.hasCondition("plains") && !pl.hasCondition("unstable") && !pl.hasCondition("high_winds"))
			pl.setGovernorType("resworld");
		else if(pl.hasCondition("dense_flora"))
			pl.setGovernorType("agrarian");
		else if(pl.hasCondition("cavernous") && !pl.hasCondition("frigid") && !pl.hasCondition("volcanic") && !pl.hasCondition("unstable") && !pl.hasCondition("high_winds"))
			pl.setGovernorType("outpost");
		else
			pl.setGovernorType("default");
	}
}

// Backwards compat function
void CapturePlanet(Event@ evt, float MakeStructures) {
	evt.obj.getState("MakeStructures").max = MakeStructures;
	CapturePlanet(evt);
}

//Caputes a target planet
//The target planet must be unowned
//Places various free structures onto the planet to help it build
void CapturePlanet(Event@ evt) {
	//if(state.val1 <= 0) {
	Object@ targ = evt.target;
	if(targ !is null && evt.obj !is null && @targ.getOwner() != @evt.obj.getOwner() && !targ.getOwner().isValid()) {
		Planet@ plt = targ.toPlanet();
		if(@plt != null) {
			Object@ obj = evt.obj;
			Empire@ owner = obj.getOwner();
			if(owner is null)
				return;

			const State@ structs = obj.getState("MakeStructures");
			float makeStructures = structs is null ? 1.f : floor(structs.max);

			StandardTakeover(plt, owner, makeStructures);

			//Send over resources in the colony ship
			State@ From, To;

			@From = evt.obj.getState("Metals");
			@To = targ.getState("Metals");
			if(@From != null && @To != null)
				To.add(From.getAvailable(), targ);

			@From = evt.obj.getState("Electronics");
			@To = targ.getState("Electronics");
			if(@From != null && @To != null)
				To.add(From.getAvailable(), targ);

			@From = evt.obj.getState("AdvParts");
			@To = targ.getState("AdvParts");
			if(@From != null && @To != null)
				To.add(From.getAvailable(), targ);

			if(canAchieve && evt.obj.getOwner() is getPlayerEmpire()) {
				progressAchievement(AID_PLANETS_SMALL, 1);
				progressAchievement(AID_PLANETS_MEDIUM, 1);
				progressAchievement(AID_PLANETS_LARGE, 1);
			}

			//state.val1 = colonizerReloadDelay;
			evt.obj.destroy(true); //Uncomment for non-reusable colony ships
		}
	}
	//}
}

void TimeModifier(Event@ evt, float Factor) {
	evt.time *= Factor;
}

float hasPower(const Object@ src, const Object@ trg, const Effector@ eff) {
	const State@ pow = trg.getState(strPower);
	if(pow is null || pow.val <= 0)
		return 0;
	return 1;
}

float hasCrew(const Object@ src, const Object@ trg, const Effector@ eff) {
	const State@ crew = trg.getState(strCrew);
	if(crew is null || crew.val <= 0)
		return 0;
	return 1;
}



void MineOre(Event@ evt, float Rate, float PowCost) {
	Object@ targ = evt.target, obj = evt.obj;
	if(targ !is null && obj !is null) {
		State@ oreTo = obj.getState(strOres), oreFrom = targ.getState(strOres);
		float duration = evt.time;

		State@ powFrom = null;
		if (PowCost > 0) {
			@powFrom = obj.getState(strPower);
			duration = min(evt.time, powFrom.getAvailable() / PowCost);
		}

		if(duration > 0) {
			float takeAmt = min(Rate * duration, min(oreTo.getTotalFreeSpace(obj), oreFrom.val));
			oreTo.add(takeAmt,obj);
			oreFrom.val -= takeAmt;

			if (PowCost > 0 && powFrom !is null)
				powFrom.consume(duration * PowCost,obj);

			if (oreFrom.val <= 0.01f && targ.toPlanet() is null)
				targ.damage(obj, pow(10, 12));
			else
				targ.damage(obj, takeAmt);
		}
	}
}

void DrainResource(Event@ evt, float Rate) {
	Object@ targ = evt.target, obj = evt.obj;
	if (evt.obj is null || !evt.obj.isValid()) {
		evt.state = ESC_DISABLE;
		return;
	}

	if(@targ != null) {
		if(evt.time > 0) {
			float used, total;
			obj.getCargoVals(used, total);

			float takeAmt = min(Rate * evt.time, total - used);
			float amt = 0.f;

			if (takeAmt <= 0.1f) {
				evt.state = ESC_DISABLE;
				return;
			}

			// Steal Adv
			State@ advTo = obj.getState(strAdvp), advFrom = targ.getState(strAdvp);
			amt = min(takeAmt / 3, advFrom.val + advFrom.inCargo);
			advFrom.consume(amt, targ);
			advTo.add(amt, obj);
			takeAmt -= amt;

			// Steal Elc
			State@ elcTo = obj.getState(strElec), elcFrom = targ.getState(strElec);
			amt = min(takeAmt / 2, elcFrom.val + elcFrom.inCargo);
			elcFrom.consume(amt, targ);
			elcTo.add(amt, obj);
			takeAmt -= amt;

			// Steal Mtl
			State@ mtlTo = obj.getState(strMetl), mtlFrom = targ.getState(strMetl);
			amt = min(takeAmt, mtlFrom.val + mtlFrom.inCargo);
			mtlFrom.consume(amt, targ);
			mtlTo.add(amt, obj);
		}
	}
}

void MakeAdvParts(Event@ evt, float Rate, float MetalCostPer, float ElectCostPer) {
	Object@ targ = evt.target;
	if(@targ != null) {
		Rate *= evt.time;
		State@ APTo = targ.getState(strAdvp);
		State@ elFrom = targ.getState(strElec), metalFrom = targ.getState(strMetl);
		float canMake = min(min(elFrom.getAvailable() / ElectCostPer, metalFrom.getAvailable() / MetalCostPer), Rate);
		canMake = min(canMake, APTo.getTotalFreeSpace(targ));
		if(canMake > 0) {
			metalFrom.consume(canMake * MetalCostPer, targ);
			elFrom.consume(canMake * ElectCostPer, targ);
			APTo.add(canMake, targ);
		}
	};
}

void RecycleMetals(Event@ evt, float PerPerson, float MaxRate) {
	Object@ targ = evt.target, obj = evt.obj;
	if(@targ != null) {
		float people = 1;
		Planet@ pl = targ.toPlanet();
		if(@pl != null)
			people = pl.getPopulation();
		State@ metals = obj.getState(strMetl);
		float recyc = min(min(people * PerPerson * evt.time, MaxRate * evt.time), metals.getTotalFreeSpace(obj));
		metals.add(recyc, obj);
	}
}

void Trade(Event@ evt, float Rate) {
	Rate *= evt.time;
	if(Rate <= 0)
		return;

	Object@ obj = evt.obj;
	Empire@ owner = obj.getOwner();

	SysRef@ ref = evt.dest;
	uint resIndex = uint(ref.val1 + 1) % 4;
	ref.val1 = resIndex;

	const string@ resName = null;
	switch(resIndex) {
		case 0:
			@resName = @strAdvp; break;
		case 1:
			@resName = @strElec; break;
		case 2:
			@resName = @strMetl; break;
		case 3: default:
			@resName = @strFood; break;
	}

	State@ resource = obj.getState(resName);
	if(resource.max > 0) {
		float resLevel = resource.val / resource.max;
		if(resLevel > 0.5f) {
			float give = min(resource.max * (resLevel - 0.5f), Rate);
			owner.addStat(resName, give);
			resource.val -= give;
		}
		else {
			float take = min(resource.max * (0.5f - resLevel), Rate);
			take = owner.consumeStat(resName, take);
			resource.val += take;
		}
	}
}

float ShouldRep(const Object@ src, const Object@ trg, const Effector@ eff) {
	const State@ dmg = trg.getState(strDamage);
	return dmg is null ? 0 : dmg.val / dmg.max;
}

float CanMine(const Object@ src, const Object@ trg, const Effector@ eff) {
	const Empire@ emp = trg.getOwner();
	if(emp is null || emp.isValid() == false)
		return 1.f;
	return 0.f;
}

void Salvage(Event@ evt, float rate, float factor) {
	Object@ targ = @evt.target;

	State@ dmg = targ.getState(strDamage);
	float hp = dmg.max - dmg.val;
	if(hp > 0) {
		Object@ src = @evt.obj;
		State@ metals = src.getState(strMetl);
		float canCollect = min(metals.getTotalFreeSpace(src), min(rate * evt.time * factor, hp * factor));
		if(canCollect > 0) {
			targ.damage(src, canCollect / factor);
			metals.add(canCollect, src);
		}
		else {
			evt.state = ESC_DISABLE;
		}
	}
	else {
		evt.state = ESC_DISABLE;
	}
}

//Extra logic for the analyzer
float UnknownHull(const Object@ from, const Object@ to, const Effector@ eff) {
	const HulledObj@ ship = @to;

	const Empire@ us = from.getOwner();
	if(us is null || us.isValid() == false)
		return 0.f;

	if(us.hasForeignHull(ship.getHull()))
		return 0.f;
	else
		return 1.f;
}

void Analyze(Event@ evt, float scanQuality, float PowCost) {
	//Consume power
	float tickCost = PowCost * evt.time;
	State@ power = evt.obj.getState(strPower);
	if(power.val < tickCost) {
		evt.state = ESC_DISABLE;
		return;
	}
	else {
		power.val -= tickCost;
	}

	//Roll the dice to see if we succeed
	//Large ships double their scanning speed on small ships, but small ships lose nearly all of their time
	if(randomf(1.f) < chanceOverTime(scanQuality,evt.time * clamp(evt.obj.radius/evt.target.radius, 0.01f, 2.f)))
		return;

	Empire@ us = evt.obj.getOwner();
	if(us is null || us.isValid() == false)
		return;

	HulledObj@ ship = @evt.target;
	us.acquireForeignHull(ship.getHull());
	evt.state = ESC_DISABLE;
}

void KillSystem(Event@ evt) {
	if (!evt.obj.isValid())
		return;
	if (evt.obj.toHulledObj() !is null)
		evt.obj.toHulledObj().damageSystem(evt.dest, evt.obj, evt.dest.HP * 2.f);
}

void SelfDestruct(Event@ evt) {
	if (!evt.obj.isValid())
		return;
	evt.dest.system.trigger("Detonation", evt.obj, null, 0, 0);
	evt.obj.destroy();
}

void CreateRingworld(Event@ evt) {
	System@ sys = evt.obj.getParent().toSystem();
	if(@sys != null && @sys.toObject() != @getGalaxy().toObject()) {
		// Check if there is already a ringworld here
		SysObjList objs;
		objs.prepare(sys);
		for (uint i = 0; i < objs.childCount; ++i) {
			Planet@ pl = objs.getChild(i);

			if (pl !is null && pl.getPhysicalType() == "ringworld") {
				// We found a ringworld, don't do anything
				evt.obj.destroy(true);
				return;
			}
		}
		objs.prepare(null);

		// Build a new ringworld
		Orbit_Desc orbDesc;
		Planet_Desc plDesc;
		plDesc.setPlanetType( getPlanetTypeID("ringworld") );
		plDesc.RandomConditions = false;
		plDesc.PlanetRadius = sys.toObject().radius * 0.5f;

		orbDesc.IsStatic = true;
		orbDesc.Offset = vector(0,0,0);
		plDesc.setOrbit(orbDesc);

		Planet@ pl = sys.makePlanet(plDesc);

		pl.addCondition("ringworld_special");

		pl.setStructureSpace(100.f);

		Object@ planet = pl.toObject();

		State@ ore = planet.getState("Ore");
		ore.max = 50000.f;
		ore.val = ore.max;

		planet.getState("Damage").max = 100000000000.f;

		StandardTakeover(planet, evt.obj.getOwner(), 25.f);

		if(canAchieve && evt.obj.getOwner() is getPlayerEmpire())
			achieve(AID_BUILD_RINGWORLD);
	}
	evt.obj.destroy(true);
}

void BankExport(Event@ evt, float Amount) {
	// Check for blockades
	System@ parent = evt.obj.getParent();
	Empire@ emp = evt.obj.getOwner();
	if (parent !is null && parent.isBlockadedFor(emp))
		return;

	// Trade a random resource
	float tickTrade = Amount * evt.time;
	const string@ resName = null;
	uint resIndex = rand(2);

	// Check which resource to trade
	switch(resIndex) {
		case 0:
			@resName = @strAdvp; break;
		case 1:
			@resName = @strElec; break;
		case 2:
			@resName = @strMetl; break;
	}

	// Trade up to a certain % of the resource
	State@ resource = evt.obj.getState(resName);
	float give = min(resource.getAvailable(), tickTrade);

	if (give >= 0.f) {
		emp.addStat(resName, give);
		resource.consume(give, evt.obj);
		tickTrade -= give;
	}
}

void MatterGen(Event@ evt, float Rate, float PowCost) {
	float tickPow = evt.time * PowCost;
	float tickRate = evt.time * Rate;

	// Check available power
	State@ pow = evt.obj.getState(strPower);
	if (pow.val <= tickPow) {
		if (pow.val <= tickPow * 0.01f)
			return;

		tickRate *= (pow.val / 2.f) / tickPow;
		tickPow = (pow.val / 2.f);
	}

	float usePerc = 0.f;
	float genFuel = 0.f;
	float genAmmo = 0.f;

	// Generate fuel
	State@ fuel = evt.obj.getState(strFuel);
	if (fuel.max > 0.f) {
		genFuel = min(fuel.max - fuel.val, tickRate);

		if (genFuel >= 0.f) {
			usePerc += genFuel / tickRate;
			fuel.val += genFuel;
		}
	}

	// Generate ammo
	State@ ammo = evt.obj.getState(strAmmo);
	if (ammo.max > 0.f) {
		genAmmo = min(ammo.max - ammo.val, tickRate - genFuel);

		if (genAmmo >= 0.f) {
			usePerc += genAmmo / tickRate;
			ammo.val += genAmmo;
		}
	}

	// Power cost
	if (usePerc >= 0.f) {
		State@ pow = evt.obj.getState(strPower);
		pow.val -= tickPow * usePerc;
	}
}

void FabricateAdv(Event@ evt, float Rate, float MtlCostPer, float ElcCostPer) {
	// Available materials
	State@ mtl = evt.obj.getState(strMetl);
	float hasMtl = mtl.getAvailable();
	float cargoMtl = mtl.inCargo;

	State@ elc = evt.obj.getState(strElec);
	float hasElc = elc.getAvailable();
	float cargoElc = elc.inCargo;

	// Figure out how much we can make
	float produce = Rate * evt.time;
	produce = min(produce, hasMtl / MtlCostPer);
	produce = min(produce, hasElc / ElcCostPer);

	State@ adv = evt.obj.getState(strAdvp);
	float space = adv.getTotalFreeSpace(evt.obj);
	space += min(produce * MtlCostPer, cargoMtl);
	space += min(produce * ElcCostPer, cargoElc);

	produce = min(space, produce);

	// Make it
	if (produce > 0) {
		evt.obj.getState(strMetl).consume(produce * MtlCostPer, evt.obj);
		evt.obj.getState(strElec).consume(produce * ElcCostPer, evt.obj);
		evt.obj.getState(strAdvp).add(produce, evt.obj);
	}
}

void AddWorkersRequired(Event@ evt, float amount) {
	evt.obj.getState(strWorkers).required += amount;
}

void SubWorkersRequired(Event@ evt, float amount) {
	evt.obj.getState(strWorkers).required -= amount;
}

void AddAdvpRequired(Event@ evt, float amount) {
	evt.obj.getState(strAdvp).required += amount;
}

void SubAdvpRequired(Event@ evt, float amount) {
	evt.obj.getState(strAdvp).required -= amount;
}

void AddElecRequired(Event@ evt, float amount) {
	evt.obj.getState(strElec).required += amount;
}

void SubElecRequired(Event@ evt, float amount) {
	evt.obj.getState(strElec).required -= amount;
}

void AddMetlRequired(Event@ evt, float amount) {
	evt.obj.getState(strMetl).required += amount;
}

void SubMetlRequired(Event@ evt, float amount) {
	evt.obj.getState(strMetl).required -= amount;
}

void AddOresRequired(Event@ evt, float amount) {
	evt.obj.getState(strOres).required += amount;
}

void SubOresRequired(Event@ evt, float amount) {
	evt.obj.getState(strOres).required -= amount;
}

void AddScrpRequired(Event@ evt, float amount) {
	evt.obj.getState(strScrp).required += amount;
}

void SubScrpRequired(Event@ evt, float amount) {
	evt.obj.getState(strScrp).required -= amount;
}

void AddFoodRequired(Event@ evt, float amount) {
	evt.obj.getState(strFood).required += amount;
}

void SubFoodRequired(Event@ evt, float amount) {
	evt.obj.getState(strFood).required -= amount;
}

void AddFuelRequired(Event@ evt, float amount) {
	evt.obj.getState(strFuel).required += amount;
}

void SubFuelRequired(Event@ evt, float amount) {
	evt.obj.getState(strFuel).required -= amount;
}

void AddAmmoRequired(Event@ evt, float amount) {
	evt.obj.getState(strAmmo).required += amount;
}

void SubAmmoRequired(Event@ evt, float amount) {
	evt.obj.getState(strAmmo).required -= amount;
}

void AddGudsRequired(Event@ evt, float amount) {
	evt.obj.getState(strGuds).required += amount;
}

void SubGudsRequired(Event@ evt, float amount) {
	evt.obj.getState(strGuds).required -= amount;
}

void AddLuxsRequired(Event@ evt, float amount) {
	evt.obj.getState(strLuxs).required += amount;
}

void SubLuxsRequired(Event@ evt, float amount) {
	evt.obj.getState(strLuxs).required -= amount;
}
