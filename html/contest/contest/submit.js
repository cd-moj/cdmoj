window.setupProblemSubmit = function(problems, updateAfterSubmit) {
    let form = document.getElementById('global-submit-form');
    let select = document.getElementById('problem-choice');
    let btn = document.getElementById('global-submit-btn');
    let msg = document.getElementById('global-submit-status');
    form.onsubmit = function(e) {
        e.preventDefault();
        let pid = select.value;
        let fileInput = document.getElementById("global-file-upload");
        if(!fileInput.files[0]) {msg.textContent="Select a file"; return;}
        let file = fileInput.files[0];
        btn.disabled = true;
        msg.innerHTML = `<span class="loader-animation"></span> Lendo arquivo...`;
        let reader = new FileReader();
        reader.onload = function(event) {
            msg.innerHTML = `<span class="loader-animation"></span> Enviando...`;
            let raw = new Uint8Array(event.target.result), binary="";
            for(let i=0;i<raw.length;i++) binary+=String.fromCharCode(raw[i]);
            let code_b64 = btoa(binary);
            fetch(`${API_SUBMIT}/${contestID}/submission/submit/`,{method:"POST",
                                                                   body:JSON.stringify({problem_id:pid,filename:file.name,code_b64:code_b64}),
                                                                   headers:{ "Content-Type":"application/json", "Bearer": TOKEN_KEY}
                                                                  }).then(r=>r.json()).then(resp=>{
                                                                      msg.innerHTML = resp.success ? "Enviado!" : `<span style="color:red">Erro: ${resp.error||"Falha"}</span>`;
                                                                      if(resp.success && typeof updateAfterSubmit === 'function') setTimeout(updateAfterSubmit, 1200);
                                                                      btn.disabled = false;
                                                                  }).catch(()=>{
                                                                      msg.textContent="Falha ao enviar."; btn.disabled = false;
                                                                  });
        };
        reader.readAsArrayBuffer(file);
    };
}
