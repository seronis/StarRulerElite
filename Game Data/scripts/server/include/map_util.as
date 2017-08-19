Planet_Desc plDesc;
Orbit_Desc orbDesc;
Star_Desc starDesc;
System_Desc sysDesc;

import Planet@ makeRandomPlanet(System@,uint,uint) from "map_generation";
import void makeRandomComet(System@) from "map_generation";
import void makeRandomAsteroid(System@, uint) from "map_generation";
import bool getMakeOddities() from "map_generation";
import void setOrbitDesc(Orbit_Desc&) from "map_generation";

const float starMassFactor = 1.f / 11000.f;
const float orbitRadiusFactor = 200.f;
const float starSizeFactor = 2.5f;
const float planetSlotRadius = 0.75f;
const float planetSlotOre = 6.f;
const float planetSlotHP = 0.7f * 1000.f;

const string@ strOre = "DeepOre", strDmg = "Damage";
const string@ strLivable = "Livable";
const string@ strAIAvoid = "AIAvoid";

Planet@ makePlanet(System@ sys, int slots, int conditions, float orbit) {
	orbDesc.Radius = orbit;

	plDesc.setOrbit(orbDesc);
	plDesc.PlanetRadius = planetSlotRadius * float(slots);
	plDesc.RandomConditions = false;

	Planet@ pl = sys.makePlanet(plDesc);
	Object@ obj = pl;

	// Set the structure slots
	pl.setStructureSpace(float(slots));

	// Add random conditions
	for (int i = 0; i < conditions; ++i)
		pl.addRandomCondition();

	// Give the planet ore
	State@ ore = obj.getState(strOre);
	ore.max = planetSlotOre * pow(float(slots) * 10.f, 3);
	ore.val = ore.max * (0.5f + randomf(0.5f));
	
	// Give the planet HP
	obj.getState(strDmg).max = pow(float(slots) * 10.f, 3) * planetSlotHP;

	return pl;
}

Star@ makeStar(System@ sys, float starSize) {
	starDesc.Temperature = randomf(2000,21000);
	starDesc.Radius = randomf(30.f + (starDesc.Temperature / 1000.f),
						60.f + (starDesc.Temperature / 600.f))
						* starSizeFactor * starSize;
	starDesc.Brightness = 1;

	orbDesc.Offset = vector(0, 0, 0);
	orbDesc.IsStatic = true;
	orbDesc.PosInYear = -1.f;
	orbDesc.setCenter(null);
	starDesc.setOrbit(orbDesc);

	orbDesc.IsStatic = false;
	orbDesc.MassRadius = starDesc.Radius;
	orbDesc.Mass = starDesc.Radius * starMassFactor;

	return sys.makeStar(starDesc);
}

System@ makeSystem(Galaxy@ Glx, vector pos, float radius) {
	sysDesc.StartRadius = radius;
	sysDesc.Position = pos;
	sysDesc.AutoStar = false;

	return Glx.createSystem(sysDesc);
}

vector makeRandomVector(float radius) {
	float theta = randomf(6.28318531f);
	return vector(radius * cos(theta), 0, radius * sin(theta));
}

void makePlanets(System@ sys, float orbit, int planets) {
	orbDesc.Radius = orbit;

	for (int i = 0; i < planets; ++i) {
		orbDesc.Radius += randomf(1.f, 2.5f) * orbitRadiusFactor;
		orbDesc.Eccentricity = randomf(0.5f, 1.5f);
		
		setOrbitDesc(orbDesc);
		makeRandomPlanet(sys, i, planets);
	}

	// Add oddities to system
	if(getMakeOddities()) {
		int comets = 1;
		while (randomf(1.f) < (0.60f / comets)) {
			makeRandomComet(sys);
			++comets;
		}
		
		int belts = 0;
		while (randomf(1.f) < 1.f / (belts + 3.f) && belts < planets) {
			makeRandomAsteroid(sys, rand(20,50));
			++belts;
		}
	}
}
