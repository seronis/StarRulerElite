//GALAXY GAS CREATION
// This script generates a spiral-galaxy styled gas

//GAS SETTINGS
//Multiplier to the sprite's size that determines the fade out distance
const float fadeOutFactor = 2.25f;

const float baseSize = 12000.f;

const float endSizeOffset = 0.125f;

const float baseSpriteCount = 425.f;

const float baseAngleInc = 8.00f;

//Amount of decay in the angle increment due to distance
const float distanceAngleDecay = 16.f;

const float armAngleVariance = 0.125f;

const float minReachFactor = 0.85f, maxReachFactor = 1.05f;

Color innerCol(20,255,255,255), outerCol(35,50,50,150);

class galacticArm {
	float reach;
	float startAngle;
};

//Returns the position of the spiral arm at a given angle
//angle: the particular angle to check (in radians, should exceed 2 pi rads to allow more than a full revolution around the galaxy)
//armStart: the angle the arm started at (in radians)
//reach: How far out the arm should reach after 1 revolution
vector spiralArm(float angle, float armStart, float reach) {
	float x = cos(angle + armStart), y = sin(angle + armStart);
	float r = reach * (angle / twoPi);
	return vector(x * r, 0, y * r);
}

//Called after the galaxy has formed
void createEnvironment(vector minBound, vector maxBound) {
	string@ dustSprite = "dust";
	float glxRadius = max(abs(min(minBound.x, minBound.z)), max(maxBound.x, maxBound.z));
	float glxHeight = (maxBound.y - minBound.y) / 2.f;
	
	float spriteSizeMult = baseSize;
	float sizeCurve = 0.67f;
	if( getGameSetting("MAP_FLATTEN", 0) == 1) {
		spriteSizeMult = baseSize / 1.35f;
		sizeCurve = 1.f;
	}
	
	uint armCount = clamp( int(getGameSetting("MAP_GALAXY_ARMS", 9)), 1, 50 );
	
	galacticArm[] arms;
	arms.resize( armCount );
	
	float armAngleSeparation = twoPi / float(armCount);
	for(uint i = 0; i < armCount; ++i) {
		arms[i].reach = randomf(glxRadius * minReachFactor, glxRadius * maxReachFactor);
		arms[i].startAngle = (armAngleSeparation * float(i)) + randomf(-armAngleVariance * armAngleSeparation, armAngleVariance * armAngleSeparation);
	}
	
	uint maxSprites = clamp( int(getGameSetting("MAP_BASE_GAS_SPRITES", baseSpriteCount) * sqrt(glxRadius / 35000.f)), armCount, int(getGameSetting("MAP_MAX_GAS_SPRITES", baseSpriteCount * 2.f)) );
	
	float angleInc = baseAngleInc * twoPi / (float(maxSprites) / float(armCount));
	float angle = 0.5f;
	for(uint i = 0; i < maxSprites; i += armCount) {
		float dist;
		for(uint arm = 0; arm < armCount; ++arm) {
			//Get the position on the arm, then randomize the result a bit
			vector spritePos = spiralArm(angle, arms[arm].startAngle, arms[arm].reach);
			dist = spritePos.getLength() + randomf(-400.f, 400.f);
			
			float pctTowardCenter = (glxRadius - dist) / glxRadius;
			
			//Rough variance
			//spritePos += vector(randomf(-1.f,1.f), randomf(-1.f,1.f), randomf(-1.f,1.f)) * randomf((1.f - pctTowardCenter) * glxRadius / 40.f);
			
			float spriteSize = spriteSizeMult * range(0.50f , 1.15f, pctTowardCenter + endSizeOffset) * pow(glxRadius / 35000.f, sizeCurve);
			spritePos.y += randomf(-1.f, 1.f) * max((glxHeight * pctTowardCenter) - spriteSize, glxHeight / 10.f);
				
			Color spriteCol = outerCol.interpolate(innerCol, dist / glxRadius);
			
			spritePos.normalize(dist);	
			createGalaxyGasSprite(dustSprite, spriteSize, spritePos, spriteCol, spriteSize * fadeOutFactor);
		}
		angle += angleInc / ( 1.f + (distanceAngleDecay * dist / glxRadius) );
	}
}
