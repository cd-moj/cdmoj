window.loadBalloonColors = async function() {
  try {
    let res = await fetch(window.API_BALLOON_COLORS, {
      headers: { "Authorization": "Bearer " + localStorage.getItem(window.TOKEN_KEY) }
    });
    let colors = await res.json();
    window.balloonColors = colors;
    return colors;
  } catch (e) {
    window.balloonColors = {};
    return {};
  }
};
