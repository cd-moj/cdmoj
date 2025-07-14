function getQueryParam(name) {
    const url = new URL(window.location.href);
    return url.searchParams.get(name) || "";
}

function getContestID(){
    let host = window.location.hostname;
    let contestID = host.split(".")[0];
    let contestIDparam=getQueryParam("contest");
    if(contestID=="moj" && contestIDparam!="") {
        contestID=`${contestIDparam}`;
        QUERYCONTEST=`?contest=${contestIDparam}`;
    }
    else if(contestID=="localhost" && contestIDparam=="")
        contestID="unknowncontest";
    else if(contestID=="localhost" && contestIDparam!="") {
        contestID=`${contestIDparam}`;
        QUERYCONTEST=`?contest=${contestIDparam}`;
    }
    else if(contestID!="moj" && contestIDparam=="")
        contestID=`contest_token_${contestID}`;
    else
        contestID="unknowncontest";
    TOKEN_KEY=`contest_token_${contestID}`;
    return contestID;
}
let contestID="unk";
