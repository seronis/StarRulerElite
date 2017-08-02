// map_lib
// =======
// Utilities and imports for various generic functionality

// {{{ Constants
// Settings
float orbitRadiusFactor = 200.f;

// Mathematical
const float Pi    = 3.14159265f;
const float twoPi = 6.28318531f;

// }}}
// {{{ Imports from game / mod
import void initMapGeneration() from "map_generation";
import float getOrbitRadiusFactor() from "map_generation";
import void setMakeOddities(bool) from "map_generation";
import System@ makeRandomSystem(Galaxy@, vector, uint, uint) from "map_generation";
import float makeQuasar(Galaxy@, vector, float) from "map_generation";
import Planet@ setupStandardHomeworld(System@, Empire@) from "map_generation";

void prepMap() {
	initMapGeneration();
	orbitRadiusFactor = getOrbitRadiusFactor();
}
// }}}
// {{{ Utilities for map generation
uint noticePctInc = 0;
uint nextNoticePct = 0;

void updateProgress(uint sysIndex, uint sysCount) {
	if (noticePctInc == 0) {
		if(sysCount < 50)
			noticePctInc = 50;
		else if(sysCount < 1000)
			noticePctInc = 25;
		else if(sysCount < 5000)
			noticePctInc = 10;
		else
			noticePctInc = 5;

		nextNoticePct = noticePctInc;
	}

	if(float(sysIndex + 1) / float(sysCount) > float(nextNoticePct) / 100.f) {
		updateLoadScreen("  "+localize("#EV_GenMap")+"... " + nextNoticePct + "%");
		nextNoticePct += noticePctInc;
	}
}

vector generateRandomVector(bool flatten, float minRad, float maxRad) {
	// Genarates a uniformly distributed random position vector between minRad
	// and maxRad away from the origin. If flatten is on, positions will only
	// vary in x and z. If minRad is equal to maxRad, the positions will form the
	// surface of a sphere or the edge of a circle.
	float theta = randomf(twoPi);

	if(!flatten) {
		float radius = range(minRad, maxRad, 1 - pow(randomf(1.f), 2));

		float u = randomf(-1.f, 1.f);

		float s = sqrt(1-(u*u));
		float x = s * cos(theta) * radius;
		float y = s * sin(theta) * radius;
		float z = u * radius;

		return vector(x, y, z);
	}
	else {
		float radius = range(minRad, maxRad, pow(randomf(1.f),0.85f));
		
		return vector(radius * cos(theta), 0.f, radius * sin(theta));
	}
}

//Turns pct into low at <=0, high at >=1, and a linear interpolation in between
float range(float low, float high, float pct) {
	return low + (clamp(0.f, 1.f, pct) * (high-low));
}

// Returns the percentage that x is between low and high
float pctBetween(float x, float low, float hi) {
	if(x <= low)
		return 0.f;
	else if(x >= hi)
		return 1.f;
	return (x - low)/(hi - low);
}
// }}}
