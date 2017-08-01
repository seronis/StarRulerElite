//CYLINDER GAS CREATION
// This script generates a cylinder of gas that can be configured to be hollow or not

//GAS SETTINGS
//Multiplier to the sprite's size that determines the fade out distance
const float fadeOutFactor = 2.25f;

const float baseSize = 19000.f;

const float baseSpriteCount = 600.f;

const float endSizeOffset = 0.125f;

//Amount of decay in the angle increment due to distance
const float distanceAngleDecay = 16.f;

Color innerCol(20,180,180,180), outerCol(35,50,50,150);

//Called after the galaxy has formed
void createEnvironment(vector minBound, vector maxBound) {
	string@ dustSprite = "dust";
	float glxRadius = abs(minBound.x - maxBound.x);
	float glxHeight = abs(minBound.y - maxBound.y);
	
	float spriteSizeMult = baseSize;
	float sizeCurve = 0.67f;
	
	uint maxSprites = clamp( int(getGameSetting("MAP_BASE_GAS_SPRITES", baseSpriteCount) * sqrt(glxRadius / 35000.f)), 1, int(getGameSetting("MAP_MAX_GAS_SPRITES", baseSpriteCount * 2.f)) );
	bool hollow = getGameSetting("MAP_HOLLOW", 0) > 0.5f;
	
	if(hollow)
		maxSprites = (maxSprites * 3) / 4;
	
	float rad, theta;
	rad = glxHeight * 0.5f;

	for (uint i = 0; i < maxSprites; ++i) {
		theta = randomf(twoPi);
		if (!hollow)
			rad = range(0, glxHeight * 0.5f, pow(randomf(1.f),0.85f));
		
		vector position = vector(randomf(-0.6f, 0.6f)*glxRadius, rad * cos(theta), rad * sin(theta));
		float dist = position.getLength();

		float spriteSize = spriteSizeMult * pow(glxRadius / 35000.f, sizeCurve);

		Color spriteCol = outerCol.interpolate(innerCol, dist / glxRadius);
		
		position.normalize(dist);	
		createGalaxyGasSprite(dustSprite, spriteSize, position, spriteCol, spriteSize * fadeOutFactor);
	}
}
