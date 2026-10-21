function setLanguage(){return;}

(function(){
  const slides=[...document.querySelectorAll('#doctorCarousel .hero-slide')];
  const dots=[...document.querySelectorAll('#doctorCarousel .carousel-dot')];
  if(slides.length<2) return;
  let current=0;
  function showSlide(n){
    current=n;
    slides.forEach((s,i)=>s.classList.toggle('active',i===n));
    dots.forEach((d,i)=>d.classList.toggle('active',i===n));
  }
  dots.forEach((d,i)=>d.addEventListener('click',()=>showSlide(i)));
  setInterval(()=>showSlide((current+1)%slides.length),2000);
})();