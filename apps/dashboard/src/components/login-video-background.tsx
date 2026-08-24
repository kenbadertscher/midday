"use client";

import { useEffect, useRef, useState } from "react";
import LoginTestimonials from "./login-testimonials";

// Upstream hardcoded a poster image and an MP4 on Midday's CDN (proxied via
// midday.ai/cdn-cgi/image/...), so simply loading the login page fetched two
// assets from Midday's servers. Both are decorative background media.
//
// Set NEXT_PUBLIC_LOGIN_POSTER_URL / NEXT_PUBLIC_LOGIN_VIDEO_URL to host your
// own. Unset (the default) renders a plain background and skips the fetches.
const LOGIN_POSTER_URL = process.env.NEXT_PUBLIC_LOGIN_POSTER_URL;
const LOGIN_VIDEO_URL = process.env.NEXT_PUBLIC_LOGIN_VIDEO_URL;

export function LoginVideoBackground() {
  const [isVideoLoaded, setIsVideoLoaded] = useState(false);
  const videoRef = useRef<HTMLVideoElement>(null);

  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;

    const handleCanPlay = () => {
      setIsVideoLoaded(true);
    };

    const handleLoadedData = () => {
      setIsVideoLoaded(true);
    };

    const handleCanPlayThrough = () => {
      setIsVideoLoaded(true);
    };

    // Check if video is already loaded
    if (video.readyState >= 3) {
      setIsVideoLoaded(true);
    }

    video.addEventListener("canplay", handleCanPlay);
    video.addEventListener("loadeddata", handleLoadedData);
    video.addEventListener("canplaythrough", handleCanPlayThrough);

    return () => {
      video.removeEventListener("canplay", handleCanPlay);
      video.removeEventListener("loadeddata", handleLoadedData);
      video.removeEventListener("canplaythrough", handleCanPlayThrough);
    };
  }, []);

  return (
    <div className="hidden lg:flex lg:w-1/2 relative overflow-hidden m-2">
      {/* Poster image with blur effect */}
      <div
        className={`absolute inset-0 w-full h-full transition-all duration-1000 ease-in-out ${
          isVideoLoaded ? "opacity-0 pointer-events-none" : "opacity-100"
        }`}
        style={{
          filter: isVideoLoaded ? "blur(0px)" : "blur(1px)",
        }}
      >
        {LOGIN_POSTER_URL && (
          <img
            src={LOGIN_POSTER_URL}
            alt=""
            className="w-full h-full object-cover"
            aria-hidden="true"
          />
        )}
      </div>

      {/* Video */}
      <video
        ref={videoRef}
        className={`absolute inset-0 w-full h-full object-cover transition-opacity duration-1000 ease-in-out ${
          isVideoLoaded ? "opacity-100" : "opacity-0"
        }`}
        autoPlay
        loop
        muted
        playsInline
        preload="auto"
        poster={LOGIN_POSTER_URL}
      >
        {LOGIN_VIDEO_URL && <source src={LOGIN_VIDEO_URL} type="video/mp4" />}
      </video>

      {/* Overlay for better text readability */}
      <div className="absolute inset-0 bg-black/20" />

      {/* Content overlay */}
      <div className="relative z-10 flex flex-col justify-center items-center p-2 text-center h-full w-full">
        <div className="max-w-lg">
          <LoginTestimonials />
        </div>
      </div>
    </div>
  );
}
