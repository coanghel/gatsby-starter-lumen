import React from "react";

import { Image } from "@/components/Image";
import { ThemeSwitcher } from "@/components/ThemeSwitcher";

import * as styles from "./Author.module.scss";

type Props = {
  author: {
    name: string;
    bio: string;
    photo: string;
  };
  url: string;
  isIndex?: boolean;
};

const Author = ({ author, isIndex, url }: Props) => (
  <div className={styles.author}>
    <a href={url}>
      <Image alt={author.name} path={author.photo} className={styles.photo} />
    </a>

    <div className={styles.titleContainer}>
      {isIndex ? (
        <h1 className={styles.title}>
          <a href={url} className={styles.link}>
            {author.name}
          </a>
        </h1>
      ) : (
        <h2 className={styles.title}>
          <a href={url} className={styles.link}>
            {author.name}
          </a>
        </h2>
      )}
      <ThemeSwitcher />
    </div>
    <p className={styles.subtitle}>{author.bio}</p>
  </div>
);

export default Author;
