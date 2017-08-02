//DUMBBELL GAS CREATION
// This script generates two sphere connected by a cylinder of gas

//GAS SETTINGS
//Multiplier to the sprite's size that determines the fade out distance
const float fadeOutFactor = 3.f;

const float baseSize = 12000.f;

const float baseSpriteCount = 185.f;

const float endSizeOffset = 0.125f;

Color innerCol(20,180,180,180), outerCol(35,50,50,150);

//Called after the galaxy has formed
void createEnvironment(vector minBound, vector maxBound) {
	string@ dustSprite = "dust";

	float glxRadius = abs(minBound.x - maxBound.x);
	float glxHeight = glxRadius * 0.33f;
	
	float spriteSizeMult = baseSize;
	float sizeCurve = 0.67f;
	
	uint maxSprites = clamp( int(getGameSetting("MAP_BASE_GAS_SPRITES", baseSpriteCount) * sqrt(glxRadius / 35000.f)), 1, int(getGameSetting("MAP_MAX_GAS_SPRITES", baseSpriteCount * 2.f)) );
	bool flatten = getGameSetting("MAP_FLATTEN", 0) > 0.5f;

	uint cntOne = maxSprites / 5 * 2;
	uint cntTwo = cntOne * 2;

	vector baseOne = vector(glxHeight, 0, 0);
	vector baseTwo = vector(-glxHeight, 0, 0);
	
	for (uint i = 0; i < maxSprites; ++i) {
		float dist;
		vector position;
		{
			if(i < cntOne) {
				position = generateRandomVector(flatten, 0.f, glxHeight * 0.5f);
				dist = position.getLength();
				position += baseOne;
			}
			else if (i < cntTwo) {
				position = generateRandomVector(flatten, 0.f, glxHeight * 0.5f);
				dist = position.getLength();
				position += baseTwo;
			}
			else {
				float theta = randomf(twoPi);
				float radius = range(0.f, glxHeight * 0.2f, pow(randomf(1.f),0.85f));

				position = vector(randomf(-1.2f, 1.2f)*glxHeight, 
					flatten ? 0.f : radius * cos(theta), radius * sin(theta));
				dist = position.getLength();
			}
		}

		float spriteSize = spriteSizeMult * pow(glxRadius / 35000.f, sizeCurve);

		Color spriteCol = outerCol.interpolate(innerCol, dist / glxHeight);
		
		position.normalize(position.getLength());	
		createGalaxyGasSprite(dustSprite, spriteSize, position, spriteCol, spriteSize * fadeOutFactor);
	}
}
