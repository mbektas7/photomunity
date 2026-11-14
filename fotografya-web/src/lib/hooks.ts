"use client";

import { useInfiniteQuery, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useRef } from "react";
import { ApiError, api } from "./api";
import type { Me, Page, PhotoCard, PhotoDetail } from "./types";

export function useMe() {
  return useQuery({
    queryKey: ["me"],
    queryFn: async () => {
      try {
        return await api<Me>("me");
      } catch (e) {
        if (e instanceof ApiError && e.status === 401) return null;
        throw e;
      }
    },
    staleTime: 60_000,
  });
}

export function usePhotoPages(key: unknown[], path: string, enabled = true) {
  return useInfiniteQuery({
    queryKey: key,
    enabled,
    initialPageParam: null as string | null,
    queryFn: ({ pageParam }) =>
      api<Page<PhotoCard>>(pageParam ? `${path}${path.includes("?") ? "&" : "?"}before=${encodeURIComponent(pageParam)}` : path),
    getNextPageParam: (last) => last.next_cursor,
  });
}

/** Görünür olduğunda bir sonraki sayfayı yükleyen gözlemci. */
export function useLoadMore(onVisible: () => void, active: boolean) {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const el = ref.current;
    if (!el || !active) return;
    const io = new IntersectionObserver((entries) => entries[0]?.isIntersecting && onVisible(), { rootMargin: "800px" });
    io.observe(el);
    return () => io.disconnect();
  }, [onVisible, active]);
  return ref;
}

type LikeTarget = Pick<PhotoCard, "id" | "liked_by_me" | "like_count">;

function patchLike<T extends LikeTarget>(item: T, id: string, liked: boolean): T {
  if (item.id !== id || item.liked_by_me === liked) return item;
  return { ...item, liked_by_me: liked, like_count: item.like_count + (liked ? 1 : -1) };
}

/** İyimser beğeni: tüm akışlardaki ve detaydaki kopyayı anında günceller, hata olursa geri alır. */
export function useLike() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ id, liked }: { id: string; liked: boolean }) =>
      api(`photos/${id}/like`, { method: liked ? "POST" : "DELETE" }),
    onMutate: async ({ id, liked }) => {
      const snapshot = qc.getQueriesData({});
      qc.setQueriesData<{ pages: Page<PhotoCard>[] } | PhotoDetail>({}, (data) => {
        if (!data || typeof data !== "object") return data;
        if ("pages" in data && Array.isArray(data.pages)) {
          return { ...data, pages: data.pages.map((p) => ({ ...p, items: p.items.map((i) => patchLike(i, id, liked)) })) };
        }
        if ("id" in data && "liked_by_me" in data) return patchLike(data as PhotoDetail, id, liked);
        return data;
      });
      return { snapshot };
    },
    onError: (_e, _v, ctx) => ctx?.snapshot.forEach(([key, value]) => qc.setQueryData(key, value)),
  });
}
