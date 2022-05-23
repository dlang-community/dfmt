int abs(int x) {
	if (x < 0)
		// x negative, must negate
		return -x;
	else
		// x already non-negative, just return it
		return x;
}