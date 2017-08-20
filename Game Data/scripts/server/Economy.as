const string@ strOres = "Ore";
const string@ strMetl = "Metals", strMine = "MineM", strMetlGen = "MetlGen";
const string@ strElec = "Electronics", strElecGen = "ElecGen";
const string@ strAdvp = "AdvParts", strAdvpGen = "AdvpGen";
const string@ strFood = "Food", strGuds = "Guds", strLuxs = "Luxs";
const string@ strLabr = "Labr";

//Provided because AS lacks e# syntax
const double million = 1000000.0;

//Conversion ratios between resources
const float ElcFromMtl = 0.5f;
const float AdvFromMtl = 1.f;
const float AdvFromElc = 1.f;

//Conversion rates when working with no resources (scales down from 1 to this value as the value/max ratio declines)
const float deadOreRate = 0.2f;
const float deadElcRate = 0.01f;
const float deadAdvRate = 0.001f;

float getRate(float val, float max, float deadRate) {
	if(max <= 0)
		return 0;
	float pct = val / max;
	if(pct <= 0)
		return deadRate;
	else if(pct >= 1.f)
		return 1.f;
	else
		return (pct * (1.f - deadRate)) + deadRate;
}

//Processes Ore into Metals
float processOre(Object@ obj, float Rate) {
	State@ resource = obj.getState(strOres);
	
	Rate *= getRate(resource.getAvailable(), resource.max, deadOreRate);
	if(Rate <= 0)
		return 0;
	
	State@ outRes = obj.getState(strMetl);
	float maxOut = outRes.getTotalFreeSpace(obj);
	float consume = Rate;

	if (obj.getOwner().hasTraitTag("lossy_mining"))
		consume *= 1.667f;
	
	if(maxOut > 0) {
		if(Rate > maxOut)
			Rate = maxOut;
		outRes.add(Rate, obj);
		resource.consume(min(consume,resource.getAvailable()), obj);
		return Rate;
	}
	return 0;
}

//Produces Electronics from Metals
float makeElectronics(Object@ obj, float Rate) {
	State@ resource = obj.getState(strMetl);
		
	const float has = resource.getAvailable();
	
	State@ outRes = obj.getState(strElec);
	float maxOut = outRes.getTotalFreeSpace(obj);
	
	if(maxOut > 0) {
		Rate = min(maxOut, Rate);
		
		float useUp = Rate / ElcFromMtl;
		if(useUp > has) {
			Rate = has * ElcFromMtl;
			useUp = has;
		}
		outRes.add(Rate, obj);
		resource.consume(useUp, obj);
		return Rate;
	}
	return 0;
}

//Produces AdvParts from Metals, Electronics
float makeAdvParts(Object@ obj, float Rate) {
	State@ mtls = obj.getState(strMetl), elects = obj.getState(strElec);
	
	const float hasM = mtls.getAvailable(), hasE = elects.getAvailable();
	
	State@ outRes = obj.getState(strAdvp);
	float maxOut = outRes.getTotalFreeSpace(obj);
	
	if(maxOut <= 0)
		return 0;
	
	Rate = min(maxOut, Rate);
	
	float useUpM = Rate / AdvFromMtl, useUpE = Rate / AdvFromElc;
	if(useUpM > hasM)
		useUpM = hasM;
	if(useUpE > hasE)
		useUpE = hasE;
	
	Rate = min(useUpM * AdvFromMtl, useUpE * AdvFromElc);
	
	outRes.add(Rate, obj);
	mtls.consume(Rate / AdvFromMtl, obj);
	elects.consume(Rate / AdvFromElc, obj);
	return Rate;
}

void produceGoods(Event@ evt, float Rate) {
	evt.target.getOwner().addStat(strGuds, Rate * evt.time);
}

void produceLuxuries(Event@ evt, float Rate) {
	evt.target.getOwner().addStat(strLuxs, Rate * evt.time);
}
